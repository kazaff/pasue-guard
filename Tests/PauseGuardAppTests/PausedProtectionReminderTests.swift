import Testing
import PauseGuardCore
@testable import PauseGuardApp

struct PausedProtectionReminderTests {
    private func runtime(_ phase: RuntimePhase = .paused, locked: Bool = false) -> RuntimeState {
        var state = RuntimeState()
        state.phase = phase
        state.locked = locked
        return state
    }

    @Test func firstReminderWaitsTenMinutesAndDisappearsAfterFiveSeconds() {
        var reminder = PausedProtectionReminderSchedule()
        let visible1 = reminder.update(runtime(), at: 100)
        #expect(!visible1)
        let visible2 = reminder.update(runtime(), at: 699.999)
        #expect(!visible2)
        let visible3 = reminder.update(runtime(), at: 700)
        #expect(visible3)
        let visible4 = reminder.update(runtime(), at: 704.999)
        #expect(visible4)
        let visible5 = reminder.update(runtime(), at: 705)
        #expect(!visible5)
        let visible6 = reminder.update(runtime(), at: 1299.999)
        #expect(!visible6)
        let visible7 = reminder.update(runtime(), at: 1300)
        #expect(visible7)
    }

    @Test func leavingPauseDismissesAndNextPauseStartsFreshWait() {
        for phase in [RuntimePhase.working, .preparing, .breaking, .stopped, .error] {
            var reminder = PausedProtectionReminderSchedule()
            let visible8 = reminder.update(runtime(), at: 0)
            #expect(!visible8)
            let visible9 = reminder.update(runtime(), at: 600)
            #expect(visible9)
            let visible10 = reminder.update(runtime(phase), at: 601)
            #expect(!visible10)
            let visible11 = reminder.update(runtime(), at: 602)
            #expect(!visible11)
            let visible12 = reminder.update(runtime(), at: 1201)
            #expect(!visible12)
            let visible13 = reminder.update(runtime(), at: 1202)
            #expect(visible13)
        }
    }

    @Test func unavailableScreenHidesReminderAndOverdueReminderAppearsOnceOnReturn() {
        var reminder = PausedProtectionReminderSchedule()
        let visible14 = reminder.update(runtime(), at: 0)
        #expect(!visible14)
        let visible15 = reminder.update(runtime(locked: true), at: 1800)
        #expect(!visible15)
        let visible16 = reminder.update(runtime(), at: 1801)
        #expect(visible16)
        let visible17 = reminder.update(runtime(locked: true), at: 1802)
        #expect(!visible17)
        let visible18 = reminder.update(runtime(), at: 1803)
        #expect(!visible18)
        let visible19 = reminder.update(runtime(), at: 2401)
        #expect(visible19)
    }

    @Test func delayedTicksDoNotReplayMissedReminders() {
        var reminder = PausedProtectionReminderSchedule()
        let visible20 = reminder.update(runtime(), at: 0)
        #expect(!visible20)
        let visible21 = reminder.update(runtime(), at: 3600)
        #expect(visible21)
        let visible22 = reminder.update(runtime(), at: 3605)
        #expect(!visible22)
        let visible23 = reminder.update(runtime(), at: 4199)
        #expect(!visible23)
        let visible24 = reminder.update(runtime(), at: 4200)
        #expect(visible24)
    }

    @Test func reminderPreservesCustomPhraseAndFallsBackForWhitespace() {
        #expect(PausedProtectionReminderView.message(for: " 别偷懒！\n开启保护。 ") == " 别偷懒！\n开启保护。 ")
        for phrase in ["", " \n\t "] {
            #expect(PausedProtectionReminderView.message(for: phrase) == "保护已暂停，请开启保护")
        }
    }
}
