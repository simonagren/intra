export interface IAlert {
    message: string;
    moreInformationUrl: string;
    type: AlertType;
}

export enum AlertType {
    Information = 1,
    Urgent
}

export interface IAlertItem {
    AlertEndDateTime: string;
    AlertMessage: string;
    AlertMoreInformation: {
        Description: string;
        Url: string;
    };
    AlertStartDateTime: string;
    AlertType: string;
}