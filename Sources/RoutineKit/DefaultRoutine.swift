import Foundation

/// Stable identifiers for the shipped defaults. They are fixed constants so that
/// notification identifiers stay deterministic across launches and reinstalls,
/// and so a v0 file can be matched task-for-task during migration.
public enum DefaultTaskID {
    public static let wake = UUID(uuidString: "A26A9A8D-7256-45C5-A633-5EAB8C896FE0")!
    public static let brushMorning = UUID(uuidString: "673EB41D-978A-47E2-ADCA-1782273E6116")!
    public static let bath = UUID(uuidString: "DB6C0C57-10B0-4AD1-A632-4EF76D411BD9")!
    public static let fajrWudu = UUID(uuidString: "38EFE96D-E991-4277-B906-28607E1D28F9")!
    public static let fajrAdhan = UUID(uuidString: "A0634EEE-B44C-45CA-A212-E2C4206EE965")!
    public static let fajrPrayer = UUID(uuidString: "40B99FA1-53FC-4D71-8B1A-9F7B71D65128")!
    public static let fajrQuran = UUID(uuidString: "179D1573-2119-4C4C-A345-109DE8CD7990")!
    public static let morningSkincare = UUID(uuidString: "EA9E79E2-8F03-4FDD-8100-1002BFE3E5D3")!
    public static let dhuhrBrush = UUID(uuidString: "F0D115A6-2C03-497C-B875-96D2AC38B549")!
    public static let dhuhrWudu = UUID(uuidString: "97E92269-2F8A-493D-AFFA-139EB9B9A4E7")!
    public static let dhuhrPrayer = UUID(uuidString: "4BA04A35-0F8C-4A3E-8C36-1C59F03E8E69")!
    public static let asrBrush = UUID(uuidString: "4D024AF4-C5DE-4CA7-ADA7-9ADDEBC988F8")!
    public static let asrWudu = UUID(uuidString: "18CE26ED-451D-468A-B8BA-D38E843E9360")!
    public static let asrPrayer = UUID(uuidString: "FF061F73-2EAD-41A3-859F-53E3E4D15544")!
    public static let maghribBrush = UUID(uuidString: "4F243B65-D49C-4787-A5F3-E156EA9B6ADA")!
    public static let maghribWudu = UUID(uuidString: "C474E9A3-E0EE-46B0-9D06-AE5FADBABC4C")!
    public static let maghribPrayer = UUID(uuidString: "4445D0C1-9401-476B-9459-0E8F1514A3C5")!
    public static let maghribQuran = UUID(uuidString: "5B0D3F04-8E90-47BD-9FDE-A70F1F15A2CF")!
    public static let ishaBrush = UUID(uuidString: "6DA5F118-6F4A-4EBD-B015-22CA4C982980")!
    public static let ishaWudu = UUID(uuidString: "6EF4902F-EC9C-4619-A6EE-F2FE5CD1AEFF")!
    public static let ishaPrayer = UUID(uuidString: "B6330640-1B35-419E-9FC3-FA1BE65CA336")!
    public static let sunscreenNoon = UUID(uuidString: "09201595-8A14-4EB5-A0F0-14197C949316")!
    public static let sunscreenAsr = UUID(uuidString: "93EA0D92-D05E-4858-8B09-805D16C7569C")!
    public static let gym = UUID(uuidString: "091F13A3-1BC7-448D-AC81-CC45202E94B7")!
    public static let returnFromGym = UUID(uuidString: "74D3D78F-98C8-4023-9698-131BB7CB02F3")!
    public static let shower = UUID(uuidString: "04F262D6-0C20-44D2-90DC-4E623F827B9F")!
    public static let dinner = UUID(uuidString: "51341300-595A-423B-9C7D-A2EC08150179")!
    public static let nightSkincare = UUID(uuidString: "C37EFB6E-F830-440E-8F21-8F615A5683F8")!
    public static let sleepReminder = UUID(uuidString: "11360370-B858-49F6-AF0E-DEC15A04C553")!

    public static let stepCleanser = UUID(uuidString: "35E634FD-4336-4160-9DB6-B4DBA8D4906D")!
    public static let stepAmpoule = UUID(uuidString: "6F5BD043-D7CB-4ED7-AFB2-226D04BD55F4")!
    public static let stepSunscreen = UUID(uuidString: "04A8F36C-79DA-4E61-82B6-3A5D5D412886")!
}

public enum DefaultRoutine {
    public static let sunscreenNote = "Skin1004 SPF 50"

    /// The five obligatory prayer tasks, always recreated by a reset.
    /// Fajr keeps its own sequence: the adhan lands at +0 and the prayer at +5.
    public static func prayerTasks() -> [RoutineTask] {
        [
            RoutineTask(id: DefaultTaskID.fajrPrayer, title: "Fajr prayer",
                        category: .prayer, timing: .anchored(prayer: .fajr, offset: 5),
                        alarm: true, protectedPrayer: .fajr),
            RoutineTask(id: DefaultTaskID.dhuhrPrayer, title: "Dhuhr prayer",
                        category: .prayer, timing: .anchored(prayer: .dhuhr, offset: 0),
                        alarm: true, protectedPrayer: .dhuhr),
            RoutineTask(id: DefaultTaskID.asrPrayer, title: "Asr prayer",
                        category: .prayer, timing: .anchored(prayer: .asr, offset: 0),
                        alarm: true, protectedPrayer: .asr),
            RoutineTask(id: DefaultTaskID.maghribPrayer, title: "Maghrib prayer",
                        category: .prayer, timing: .anchored(prayer: .maghrib, offset: 0),
                        alarm: true, protectedPrayer: .maghrib),
            RoutineTask(id: DefaultTaskID.ishaPrayer, title: "Isha prayer",
                        category: .prayer, timing: .anchored(prayer: .isha, offset: 0),
                        alarm: true, protectedPrayer: .isha)
        ]
    }

    public static func tasks() -> [RoutineTask] {
        var tasks: [RoutineTask] = []

        // ---- Fajr sequence -------------------------------------------------
        tasks.append(RoutineTask(id: DefaultTaskID.wake, title: "Wake up",
                                 category: .wake,
                                 timing: .fixed(RoutineSettings.defaultWakeTime),
                                 alarm: true, insistent: true))
        tasks.append(RoutineTask(id: DefaultTaskID.brushMorning, title: "Brush teeth",
                                 category: .hygiene,
                                 timing: .fixed(TimeOfDay(hour: 4, minute: 55))))
        tasks.append(RoutineTask(id: DefaultTaskID.bath, title: "Bath",
                                 category: .hygiene,
                                 timing: .fixed(TimeOfDay(hour: 5, minute: 0))))
        tasks.append(RoutineTask(id: DefaultTaskID.fajrWudu, title: "Wudu",
                                 category: .hygiene,
                                 timing: .anchored(prayer: .fajr, offset: -10),
                                 isPrayerPreparation: true))
        tasks.append(RoutineTask(id: DefaultTaskID.fajrAdhan, title: "Fajr / Adhan",
                                 category: .prayer,
                                 timing: .anchored(prayer: .fajr, offset: 0)))
        tasks.append(prayerTasks()[0])                                   // Fajr + 5
        tasks.append(RoutineTask(id: DefaultTaskID.fajrQuran, title: "Read Quran",
                                 category: .quran,
                                 timing: .anchored(prayer: .fajr, offset: 15)))
        tasks.append(RoutineTask(id: DefaultTaskID.morningSkincare, title: "Morning skincare",
                                 category: .skincare,
                                 timing: .anchored(prayer: .fajr, offset: 40),
                                 steps: [
                                    ChecklistStep(id: DefaultTaskID.stepCleanser,
                                                  name: "Round Lab Dokdo Cleanser"),
                                    ChecklistStep(id: DefaultTaskID.stepAmpoule,
                                                  name: "Dr. Althea 345"),
                                    ChecklistStep(id: DefaultTaskID.stepSunscreen,
                                                  name: "Skin1004 SPF 50")
                                 ]))

        // ---- Dhuhr / Asr / Maghrib / Isha ----------------------------------
        // Same three steps every time: brush -20, wudu -10, prayer +0.
        let later: [(Prayer, UUID, UUID, RoutineTask)] = [
            (.dhuhr, DefaultTaskID.dhuhrBrush, DefaultTaskID.dhuhrWudu, prayerTasks()[1]),
            (.asr, DefaultTaskID.asrBrush, DefaultTaskID.asrWudu, prayerTasks()[2]),
            (.maghrib, DefaultTaskID.maghribBrush, DefaultTaskID.maghribWudu, prayerTasks()[3]),
            (.isha, DefaultTaskID.ishaBrush, DefaultTaskID.ishaWudu, prayerTasks()[4])
        ]
        for (prayer, brushID, wuduID, prayerTask) in later {
            tasks.append(RoutineTask(id: brushID, title: "Brush teeth",
                                     category: .hygiene,
                                     timing: .anchored(prayer: prayer, offset: -20),
                                     isPrayerPreparation: true))
            tasks.append(RoutineTask(id: wuduID, title: "Wudu",
                                     category: .hygiene,
                                     timing: .anchored(prayer: prayer, offset: -10),
                                     isPrayerPreparation: true))
            tasks.append(prayerTask)
            if prayer == .maghrib {
                tasks.append(RoutineTask(id: DefaultTaskID.maghribQuran, title: "Read Quran",
                                         category: .quran,
                                         timing: .anchored(prayer: .maghrib, offset: 15)))
            }
        }

        // ---- Going-out only ------------------------------------------------
        tasks.append(RoutineTask(id: DefaultTaskID.sunscreenNoon,
                                 title: "Extra sunscreen - Noon",
                                 note: sunscreenNote,
                                 category: .skincare,
                                 timing: .fixed(TimeOfDay(hour: 12, minute: 0)),
                                 onlyWhenGoingOut: true))
        tasks.append(RoutineTask(id: DefaultTaskID.sunscreenAsr,
                                 title: "Extra sunscreen - Asr",
                                 note: sunscreenNote,
                                 category: .skincare,
                                 timing: .anchored(prayer: .asr, offset: -30),
                                 onlyWhenGoingOut: true))

        // ---- Evening -------------------------------------------------------
        tasks.append(RoutineTask(id: DefaultTaskID.gym, title: "Gym",
                                 category: .gym,
                                 timing: .fixed(TimeOfDay(hour: 20, minute: 40))))
        tasks.append(RoutineTask(id: DefaultTaskID.returnFromGym, title: "Return from gym",
                                 category: .gym,
                                 timing: .fixed(TimeOfDay(hour: 21, minute: 30))))
        tasks.append(RoutineTask(id: DefaultTaskID.shower, title: "Shower",
                                 category: .hygiene,
                                 timing: .fixed(TimeOfDay(hour: 21, minute: 35))))
        tasks.append(RoutineTask(id: DefaultTaskID.dinner, title: "Dinner",
                                 category: .meal,
                                 timing: .fixed(TimeOfDay(hour: 21, minute: 45))))
        tasks.append(RoutineTask(id: DefaultTaskID.nightSkincare, title: "Night skincare",
                                 category: .skincare,
                                 timing: .fixed(TimeOfDay(hour: 22, minute: 0)),
                                 steps: []))
        tasks.append(RoutineTask(id: DefaultTaskID.sleepReminder, title: "Sleep reminder",
                                 category: .sleep,
                                 timing: .fixed(TimeOfDay(hour: 22, minute: 15))))

        return tasks
    }
}
