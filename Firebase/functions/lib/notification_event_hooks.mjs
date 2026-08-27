// REVIEW-ONLY, UNDEPLOYED hooks. Call only after the source transaction commits.
import { writeNotificationOutbox } from './notification_outbox_writer.mjs';

export const emitNotificationAfterCommit = (writer, event) => writer(event);
export const createNotificationHooks = ({ firestore }) => ({
  parentLinkCreated: event => emitNotificationAfterCommit(writeNotificationOutbox, { firestore, ...event, eventType: 'parentLinkCreated', route: 'children' }),
  parentLinkRevoked: event => emitNotificationAfterCommit(writeNotificationOutbox, { firestore, ...event, eventType: 'parentLinkRevoked', route: 'children' }),
  classScheduleChanged: event => emitNotificationAfterCommit(writeNotificationOutbox, { firestore, ...event, eventType: 'classScheduleChanged', route: 'myClasses' }),
  instituteNotice: event => emitNotificationAfterCommit(writeNotificationOutbox, { firestore, ...event, eventType: 'instituteNotice', route: 'notices' }),
});
