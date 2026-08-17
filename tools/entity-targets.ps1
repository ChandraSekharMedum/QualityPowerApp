# entity-targets.ps1 -- the F&O data entities Phase 1 needs as virtual tables.
# Names are the mserp_physicalname values in the catalogue (case-insensitive match).
# Grouped by the screen family from QM-ARCH-001 section 6.

$script:EntityTargets = @(
    # --- Quality order + results ---
    @{ Name='INVENTQUALITYORDERLINEENTITYPOWERAPP';                    Area='QO lines';        Why='Result entry lines, app-optimised' }
    @{ Name='POWERAPPINVENTQOLINEENTITY';                              Area='QO lines';        Why='Result entry lines, alternate' }
    @{ Name='InventQualityTestGroupEntity';                            Area='Test setup';      Why='Test group picker' }
    @{ Name='InventQualityTestVariableOutcomeEntity';                  Area='Test setup';      Why='Outcome options' }
    @{ Name='POWERAPPSINVENTTESTVARIABLEOUTCOMEENTITY';                Area='Test setup';      Why='Outcome options, app-optimised' }

    # --- Non-conformance ---
    @{ Name='POWERAPPSINVENTNONCONFORMATIONENTITY';                    Area='NC';              Why='NC form, app-optimised' }
    @{ Name='INVENTPROBLEMTYPEDATAENTITY';                             Area='NC';              Why='Problem type picker' }

    # --- Batch disposition ---
    @{ Name='POWERAPPSPDSDISPOSITIONMASTERENTITY';                     Area='Disposition';     Why='Disposition code master' }
    @{ Name='INVENTBATCHENTITY';                                       Area='Disposition';     Why='Batch lookup' }
    @{ Name='POWERAPPINVENTBATCHTMPENTITY';                            Area='Disposition';     Why='Batch scan staging' }
    @{ Name='POWERAPPBATCHTRACINGONHAND';                              Area='Disposition';     Why='Batch on-hand for disposition' }

    # --- Inventory dimensions ---
    @{ Name='POWERAPPSINVENTSITE';                                     Area='Dimensions';      Why='Site picker' }
    @{ Name='POWERAPPSINVENTLOCATION';                                 Area='Dimensions';      Why='Location picker' }
    @{ Name='POWERAPPSWHSINVENTSTATUSENTITY';                          Area='Dimensions';      Why='Inventory status' }
    @{ Name='POWERAPPSWHSLICENSEPLATEENTITY';                          Area='Dimensions';      Why='License plate' }
    @{ Name='POWERAPPSINVENTCOLOR';                                    Area='Dimensions';      Why='Colour variant' }
    @{ Name='POWERAPPINVENTDIMCOMBENTITY';                             Area='Dimensions';      Why='Dimension combination' }
    @{ Name='POWERAPPSECORESPRODUCTDIMENSIONGROUPPRODUCTENTITY';       Area='Dimensions';      Why='Which dims apply per product' }
    @{ Name='POWERAPPINVENTTABLESTOREDIMGRPENTITY';                    Area='Dimensions';      Why='Storage dimension group' }

    # --- Reference orders ---
    @{ Name='POWERAPPSPRODTABLEENTITY';                                Area='Production';      Why='Production order picker' }
    @{ Name='POWERAPPSPRODPRODUCTIONORDERROUTEOPERATIONENTITY';        Area='Production';      Why='Route operation picker' }
    @{ Name='POWERAPPPRODBATCHORDERCOPRODUCTENTITY';                   Area='Production';      Why='Co-product batch order' }
    @{ Name='POWERAPPSWRKCTRTABLEENTITY';                              Area='Production';      Why='Work centre for route ops' }
    @{ Name='POWERAPPSCUSTTABLEENTITY';                                Area='Accounts';        Why='Customer picker' }

    # --- Items and on-hand ---
    @{ Name='POWERAPPSINVENTTABLEINVENTORYENTITY';                     Area='Items';           Why='Item picker with inventory' }
    @{ Name='POWERAPPINVENTSUMENTITY';                                 Area='Items';           Why='On-hand quantities' }

    # --- Attachments (risk R1) ---
    @{ Name='POWERAPPSIMAGESSTAGING';                                  Area='Attachments';     Why='R1 - photo staging' }
    @{ Name='POWERAPPFILESAVINGENTITY';                                Area='Attachments';     Why='R1 - file save path' }
)
