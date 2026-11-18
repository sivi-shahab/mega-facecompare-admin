CREATE TABLE public.app (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    guid character varying(36) NOT NULL,
    api_key character varying(36) NOT NULL
);
CREATE SEQUENCE public.app_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
CREATE TABLE public.databasechangelog (
    id character varying(255) NOT NULL,
    author character varying(255) NOT NULL,
    filename character varying(255) NOT NULL,
    dateexecuted timestamp without time zone NOT NULL,
    orderexecuted integer NOT NULL,
    exectype character varying(10) NOT NULL,
    md5sum character varying(35),
    description character varying(255),
    comments character varying(255),
    tag character varying(255),
    liquibase character varying(20),
    contexts character varying(255),
    labels character varying(255),
    deployment_id character varying(10)
);
CREATE TABLE public.databasechangeloglock (
    id integer NOT NULL,
    locked boolean NOT NULL,
    lockgranted timestamp without time zone,
    lockedby character varying(255)
);
CREATE TABLE public.embedding (
    id uuid NOT NULL,
    subject_id uuid,
    embedding double precision[] NOT NULL,
    calculator character varying(255) NOT NULL,
    img_id uuid
);
CREATE TABLE public.img (
    id uuid NOT NULL,
    content bytea NOT NULL
);
CREATE TABLE public.install_info (
    install_guid character varying(36)
);
CREATE TABLE public.model (
    id bigint NOT NULL,
    name character varying(255) NOT NULL,
    guid character varying(36) NOT NULL,
    app_id bigint NOT NULL,
    api_key character varying(36) NOT NULL,
    type character varying(1) NOT NULL,
    created_date timestamp without time zone
);
CREATE SEQUENCE public.model_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
CREATE TABLE public.model_statistic (
    id bigint NOT NULL,
    request_count integer NOT NULL,
    model_id bigint NOT NULL,
    created_date timestamp without time zone NOT NULL
);
CREATE SEQUENCE public.model_statistic_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
CREATE TABLE public.oauth_access_token (
    token_id character varying(255),
    token bytea,
    authentication_id character varying(255) NOT NULL,
    user_name character varying(255),
    client_id character varying(255),
    authentication bytea,
    refresh_token character varying(255),
    expiration timestamp without time zone NOT NULL
);
CREATE TABLE public.oauth_client_details (
    client_id character varying(50) NOT NULL,
    access_token_validity integer,
    additional_information character varying(255),
    authorities character varying(255) NOT NULL,
    authorized_grant_types character varying(255) NOT NULL,
    auto_approve character varying(255),
    client_secret character varying(255),
    refresh_token_validity integer,
    resource_ids character varying(255) NOT NULL,
    scope character varying(255) NOT NULL
);
CREATE TABLE public.oauth_refresh_token (
    token_id character varying(255),
    token bytea,
    authentication bytea,
    expiration timestamp without time zone NOT NULL
);
CREATE SEQUENCE public.organization_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
CREATE TABLE public.reset_password_token (
    token uuid NOT NULL,
    user_email character varying(63) NOT NULL,
    expires_in timestamp without time zone NOT NULL
);
CREATE TABLE public.subject (
    id uuid NOT NULL,
    api_key character varying(36),
    subject_name character varying(255)
);
CREATE TABLE public.table_lock (
    id uuid NOT NULL,
    lock_name character varying(50) NOT NULL
);
CREATE TABLE public."user" (
    id bigint NOT NULL,
    email character varying(63) NOT NULL,
    password character varying(255) NOT NULL,
    first_name character varying(63) NOT NULL,
    last_name character varying(63) NOT NULL,
    account_non_expired boolean NOT NULL,
    account_non_locked boolean NOT NULL,
    credentials_non_expired boolean NOT NULL,
    enabled boolean NOT NULL,
    registration_token character varying(36),
    guid character varying(36) NOT NULL,
    reg_time timestamp without time zone,
    global_role character varying(1),
    allow_statistics boolean DEFAULT false
);
CREATE TABLE public.user_app_role (
    app_id bigint NOT NULL,
    user_id bigint NOT NULL,
    role character varying(1) NOT NULL
);
CREATE SEQUENCE public.user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER TABLE ONLY public.subject
    ADD CONSTRAINT api_key_subject_name_uindex UNIQUE (api_key, subject_name);
ALTER TABLE ONLY public.app
    ADD CONSTRAINT app_api_key_uindex UNIQUE (api_key);
ALTER TABLE ONLY public.app
    ADD CONSTRAINT app_guid_uindex UNIQUE (guid);
ALTER TABLE ONLY public.model
    ADD CONSTRAINT app_name_app_id_uindex UNIQUE (name, app_id);
ALTER TABLE ONLY public.databasechangeloglock
    ADD CONSTRAINT databasechangeloglock_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.install_info
    ADD CONSTRAINT install_guid UNIQUE (install_guid);
ALTER TABLE ONLY public.model
    ADD CONSTRAINT model_api_key_uindex UNIQUE (api_key);
ALTER TABLE ONLY public.model
    ADD CONSTRAINT model_guid_uindex UNIQUE (guid);
ALTER TABLE ONLY public.app
    ADD CONSTRAINT pk_app PRIMARY KEY (id);
ALTER TABLE ONLY public.oauth_access_token
    ADD CONSTRAINT pk_cauthentication_id PRIMARY KEY (authentication_id);
ALTER TABLE ONLY public.oauth_client_details
    ADD CONSTRAINT "pk_clientId" PRIMARY KEY (client_id);
ALTER TABLE ONLY public.embedding
    ADD CONSTRAINT pk_embedding PRIMARY KEY (id);
ALTER TABLE ONLY public.img
    ADD CONSTRAINT pk_img PRIMARY KEY (id);
ALTER TABLE ONLY public.model
    ADD CONSTRAINT pk_model PRIMARY KEY (id);
ALTER TABLE ONLY public.model_statistic
    ADD CONSTRAINT pk_model_statistic PRIMARY KEY (id);
ALTER TABLE ONLY public.reset_password_token
    ADD CONSTRAINT pk_reset_password_token PRIMARY KEY (token);
ALTER TABLE ONLY public.subject
    ADD CONSTRAINT pk_subject PRIMARY KEY (id);
ALTER TABLE ONLY public.table_lock
    ADD CONSTRAINT pk_table_lock PRIMARY KEY (id);
ALTER TABLE ONLY public."user"
    ADD CONSTRAINT pk_user PRIMARY KEY (id);
ALTER TABLE ONLY public.user_app_role
    ADD CONSTRAINT pk_user_app_role PRIMARY KEY (app_id, user_id);
ALTER TABLE ONLY public.reset_password_token
    ADD CONSTRAINT reset_password_token_user_email_uindex UNIQUE (user_email);
ALTER TABLE ONLY public.table_lock
    ADD CONSTRAINT table_lock_lock_name_uindex UNIQUE (lock_name);
ALTER TABLE ONLY public."user"
    ADD CONSTRAINT user_email_uindex UNIQUE (email);
ALTER TABLE ONLY public."user"
    ADD CONSTRAINT user_guid_uindex UNIQUE (guid);
ALTER TABLE ONLY public.model
    ADD CONSTRAINT fk_app_id FOREIGN KEY (app_id) REFERENCES public.app(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY public.user_app_role
    ADD CONSTRAINT fk_app_id FOREIGN KEY (app_id) REFERENCES public.app(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY public.embedding
    ADD CONSTRAINT fk_img_id FOREIGN KEY (img_id) REFERENCES public.img(id);
ALTER TABLE ONLY public.model_statistic
    ADD CONSTRAINT fk_model_id FOREIGN KEY (model_id) REFERENCES public.model(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY public.reset_password_token
    ADD CONSTRAINT fk_reset_password_token_user_email FOREIGN KEY (user_email) REFERENCES public."user"(email) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY public.embedding
    ADD CONSTRAINT fk_subject_id FOREIGN KEY (subject_id) REFERENCES public.subject(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY public.subject
    ADD CONSTRAINT fk_subject_model_api_key FOREIGN KEY (api_key) REFERENCES public.model(api_key) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE ONLY public.user_app_role
    ADD CONSTRAINT fk_user_id FOREIGN KEY (user_id) REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE;
