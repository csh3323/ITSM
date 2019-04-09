# --
# Copyright (C) 2001-2019 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package var::packagesetup::ITSM;    ## no critic

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::Package',
);

=head1 NAME

var::packagesetup::ITSM - code to execute during package installation

=head1 PUBLIC INTERFACE

=head2 new()

create an object

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $CodeObject = $Kernel::OM->Get('var::packagesetup::ITSM');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # Force a reload of ZZZAuto.pm and ZZZAAuto.pm to get the fresh configuration values.
    for my $Module ( sort keys %INC ) {
        if ( $Module =~ m/ZZZAA?uto\.pm$/ ) {
            delete $INC{$Module};
        }
    }

    # Create common objects with fresh default config.
    $Kernel::OM->ObjectsDiscard();

    # define path to the packages
    $Self->{PackagePath} = '/var/packagesetup/ITSM/';

    # define package names
    $Self->{PackageNames} = [
        'GeneralCatalog',
        'ITSMCore',
        'ITSMIncidentProblemManagement',
        'ITSMConfigurationManagement',
        'ITSMChangeManagement',
        'ITSMServiceLevelManagement',
        'ImportExport',
    ];

    # define the version of the included packages
    $Self->{PackageVersion} = '6.0.18';

    # define miminum required itsm version (if installed already)
    $Self->{MinimumITSMVersion} = '1.3.1';

    # delete some modules from %INC to prevent errors
    # when updating older ITSM packages
    delete $INC{'Kernel/System/GeneralCatalog.pm'};
    delete $INC{'Kernel/System/ITSMConfigItem.pm'};

    return $Self;
}

=head2 CodeInstall()

run the code install part

    my $Result = $CodeObject->CodeInstall();

=cut

sub CodeInstall {
    my ( $Self, %Param ) = @_;

    # check requirements
    my $ResultOk = $Self->_CheckRequirements();

    if ($ResultOk) {

        # install the ITSM packages
        $ResultOk = $Self->_InstallITSMPackages();
    }

    else {

        # error handling
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Installation failed! See syslog for details.",
        );

        # uninstall this package
        $Self->_UninstallPackage(
            PackageList    => ['ITSM'],
            PackageVersion => $Self->{PackageVersion},
        );

        return;
    }

    return 1;
}

=head2 CodeUpgrade()

run the code upgrade part

    my $Result = $CodeObject->CodeUpgrade();

=cut

sub CodeUpgrade {
    my ( $Self, %Param ) = @_;

    # check requirements
    my $ResultOk = $Self->_CheckRequirements();

    if ($ResultOk) {

        # install the ITSM packages
        $ResultOk = $Self->_InstallITSMPackages();
    }

    else {

        # error handling
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Installation failed! See syslog for details.",
        );

        # uninstall this package
        $Self->_UninstallPackage(
            PackageList    => ['ITSM'],
            PackageVersion => $Self->{PackageVersion},
        );

        return;
    }

    return 1;
}

=head2 CodeUninstall()

run the code uninstall part

    my $Result = $CodeObject->CodeUninstall();

=cut

sub CodeUninstall {
    my ( $Self, %Param ) = @_;

    # get the reverse package list
    my @ReversePackageList = reverse @{ $Self->{PackageNames} };

    # uninstall the packages
    $Self->_UninstallPackage(
        PackageList    => \@ReversePackageList,
        PackageVersion => $Self->{PackageVersion},
    );

    return 1;
}

=begin Internal:

=head2 _InstallITSMPackages()

installes the itsm packages

    my $Result = $CodeObject->_InstallITSMPackages();

=cut

sub _InstallITSMPackages {
    my ( $Self, %Param ) = @_;

    # install/upgrade the packages
    PACKAGE:
    for my $PackageName ( @{ $Self->{PackageNames} } ) {

        # create the file location
        my $FileLocation = $Kernel::OM->Get('Kernel::Config')->Get('Home')
            . $Self->{PackagePath}
            . $PackageName . '.opm';

        # read the content of the OPM file
        my $FileContent = $Kernel::OM->Get('Kernel::System::Main')->FileRead(
            Location        => $FileLocation,
            Mode            => 'binmode',
            Result          => 'SCALAR',
            DisableWarnings => 1,
        );

        next PACKAGE if !${$FileContent};

        # install/upgrade the package
        $Kernel::OM->Get('Kernel::System::Package')->PackageInstall(
            String => ${$FileContent},
        );
    }

    return 1;
}

=head2 _CheckRequirements()

check requirements

    my $Result = $CodeObject->_CheckRequirements();

=cut

sub _CheckRequirements {
    my ( $Self, %Param ) = @_;

    # build a lookup hash of all ITSM package names
    my %ITSMPackage = map { $_ => 1 } @{ $Self->{PackageNames} };

    # get list of all installed packages
    my @RepositoryList = $Kernel::OM->Get('Kernel::System::Package')->RepositoryList();

    PACKAGE:
    for my $Package (@RepositoryList) {

        # package is not an ITSM package
        next PACKAGE if !$ITSMPackage{ $Package->{Name}->{Content} };

        # check if the package version version is at least the minimum required itsm version
        my $CheckVersion = $Self->_CheckVersion(
            Version1 => $Self->{MinimumITSMVersion},
            Version2 => $Package->{Version}->{Content},
            Type     => 'Min',
        );

        # itsm modul version is higher than minimum version
        next PACKAGE if $CheckVersion;

        # error handling
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Package '$Package->{Name}->{Content}' "
                . "version $Package->{Version}->{Content} is installed. "
                . "You need to upgrade to at least version $Self->{MinimumITSMVersion} first!",
        );

        return;
    }

    # check files
    FILE:
    for my $File ( @{ $Self->{PackageNames} } ) {

        # create file location
        my $Location = $Kernel::OM->Get('Kernel::Config')->Get('Home')
            . $Self->{PackagePath}
            . $File . '.opm';

        if ( !-f $Location ) {

            # error handling
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Could not find file $File!",
            );

            return;
        }

        # read the content of the file
        my $FileContent = $Kernel::OM->Get('Kernel::System::Main')->FileRead(
            Location        => $Location,
            Mode            => 'binmode',
            Result          => 'SCALAR',
            DisableWarnings => 1,
        );

        # file is ok
        if ( $FileContent && ref $FileContent eq 'SCALAR' && ${$FileContent} ) {
            next FILE;
        }

        # error handling
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Could not read file $File correctly!",
        );

        return;
    }

    return 1;
}

=head2 _UninstallPackage()

uninstalls packages, but only if the packages match the given package version

    my $Success = $CodeObject->_UninstallPackage(
        PackageList    => [ 'ITSMCore', 'GeneralCatalog' ],
        PackageVersion => '2.0.2',
    );

=cut

sub _UninstallPackage {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Attribute (qw(PackageList PackageVersion)) {
        if ( !$Param{$Attribute} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Attribute!",
            );
            return;
        }
    }

    # get list of packages to uninstall
    my @PackageList = @{ $Param{PackageList} };

    # get list of all installed packages
    my @RepositoryList = $Kernel::OM->Get('Kernel::System::Package')->RepositoryList();

    for my $Package (@PackageList) {

        REPOSITORYPACKAGE:
        for my $RepositoryPackage (@RepositoryList) {

            next REPOSITORYPACKAGE if $RepositoryPackage->{Name}->{Content} ne $Package;
            next REPOSITORYPACKAGE
                if $RepositoryPackage->{Version}->{Content} ne $Param{PackageVersion};

            # get package content from repository
            my $PackageContent = $Kernel::OM->Get('Kernel::System::Package')->RepositoryGet(
                Name    => $RepositoryPackage->{Name}->{Content},
                Version => $RepositoryPackage->{Version}->{Content},
            );

            # uninstall the package
            $Kernel::OM->Get('Kernel::System::Package')->PackageUninstall(
                String => $PackageContent,
            );
        }
    }

    return 1;
}

=head2 _CheckVersion()

checks if Version2 is at least Version1

    my $Result = $CodeObject->_CheckVersion(
        Version1 => '1.3.1',
        Version2 => '1.2.4',
        Type     => 'Min',
    );

=cut

sub _CheckVersion {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Attribute (qw(Version1 Version2 Type)) {
        if ( !defined $Param{$Attribute} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "$Attribute not defined!",
            );
            return;
        }
    }
    for my $Type (qw(Version1 Version2)) {
        my @Parts = split( /\./, $Param{$Type} );
        $Param{$Type} = 0;
        for my $Position ( 0 .. 4 ) {
            if ( defined $Parts[$Position] ) {
                $Param{$Type} .= sprintf( "%04d", $Parts[$Position] );
            }
            else {
                $Param{$Type} .= '0000';
            }
        }
        $Param{$Type} = int( $Param{$Type} );
    }
    if ( $Param{Type} eq 'Min' ) {
        return 1 if ( $Param{Version2} >= $Param{Version1} );
        return;
    }
    elsif ( $Param{Type} eq 'Max' ) {
        return 1 if ( $Param{Version2} < $Param{Version1} );
        return;
    }

    $Kernel::OM->Get('Kernel::System::Log')->Log(
        Priority => 'error',
        Message  => 'Invalid Type!',
    );
    return;
}

1;

=end Internal:

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<https://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (GPL). If you
did not receive this file, see L<https://www.gnu.org/licenses/gpl-3.0.txt>.

=cut
