--
-- PostgreSQL database dump
--

\restrict vwnjOLMufZFL4VHgIEUAHLFJhpYX1cHuMh7G8nNolMAdkvzuFWWRc2ozbIGdM6T

-- Dumped from database version 18.6 (Ubuntu 18.6-0ubuntu0.26.04.1)
-- Dumped by pg_dump version 18.6 (Ubuntu 18.6-0ubuntu0.26.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: blocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blocks (
    blocker_id character varying(9) NOT NULL,
    blocked_id character varying(9) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: businesses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.businesses (
    id uuid NOT NULL,
    owner_id character varying(9) NOT NULL,
    name character varying(80) NOT NULL,
    category character varying(30) NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    lat double precision NOT NULL,
    lng double precision NOT NULL,
    address character varying(160),
    phone character varying(30),
    hours character varying(120),
    cover_url text,
    verified boolean DEFAULT false NOT NULL,
    status character varying(12) DEFAULT 'pending'::character varying NOT NULL,
    vessel_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comments (
    id uuid NOT NULL,
    post_id uuid NOT NULL,
    author_id character varying(9) NOT NULL,
    text text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contacts (
    owner_id character varying(9) NOT NULL,
    contact_id character varying(9) NOT NULL
);


--
-- Name: districts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.districts (
    id integer NOT NULL,
    city character varying(20) DEFAULT 'jeddah'::character varying NOT NULL,
    osm_id character varying(20),
    name_ar character varying(80) NOT NULL,
    name_en character varying(80),
    lat double precision NOT NULL,
    lng double precision NOT NULL,
    vessel_id uuid
);


--
-- Name: districts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.districts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: districts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.districts_id_seq OWNED BY public.districts.id;


--
-- Name: mailbox; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mailbox (
    id uuid NOT NULL,
    recipient_id character varying(9) NOT NULL,
    envelope jsonb NOT NULL,
    queued_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: map_pins; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.map_pins (
    id uuid NOT NULL,
    owner_id character varying(9) NOT NULL,
    lat double precision NOT NULL,
    lng double precision NOT NULL,
    type character varying(10) NOT NULL,
    content text NOT NULL,
    place_name character varying(80),
    rating smallint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone
);


--
-- Name: map_presence; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.map_presence (
    user_id character varying(9) NOT NULL,
    lat double precision NOT NULL,
    lng double precision NOT NULL,
    title character varying(60),
    visible boolean DEFAULT false NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages (
    id uuid NOT NULL,
    sender_id character varying(9) NOT NULL,
    recipient_id character varying(9) NOT NULL,
    type character varying(12) NOT NULL,
    content text NOT NULL,
    sent_at timestamp with time zone DEFAULT now() NOT NULL,
    delivered_at timestamp with time zone,
    read_at timestamp with time zone
);


--
-- Name: posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posts (
    id uuid NOT NULL,
    vessel_id uuid NOT NULL,
    author_id character varying(9) NOT NULL,
    type character varying(10) NOT NULL,
    content text NOT NULL,
    caption text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    kind character varying(12) DEFAULT 'discussion'::character varying NOT NULL,
    tag character varying(16)
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    user_id character varying(9) NOT NULL,
    bio text DEFAULT ''::text NOT NULL,
    voice_intro_url text,
    skills jsonb DEFAULT '[]'::jsonb NOT NULL,
    hobbies jsonb DEFAULT '[]'::jsonb NOT NULL,
    looking_for jsonb DEFAULT '[]'::jsonb NOT NULL,
    offerings jsonb DEFAULT '[]'::jsonb NOT NULL,
    account_type character varying(10) DEFAULT 'personal'::character varying NOT NULL,
    visibility jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_public boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: push_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.push_subscriptions (
    endpoint text NOT NULL,
    user_id character varying(9) NOT NULL,
    subscription jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reports (
    id uuid NOT NULL,
    reporter_id character varying(9) NOT NULL,
    reported_id character varying(9) NOT NULL,
    reason character varying(20) NOT NULL,
    message_id uuid,
    details text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    status character varying(12) DEFAULT 'new'::character varying NOT NULL
);


--
-- Name: request_ignores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_ignores (
    user_id character varying(9) NOT NULL,
    peer_id character varying(9) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    token text NOT NULL,
    user_id character varying(9) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL
);


--
-- Name: stories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stories (
    id uuid NOT NULL,
    user_id character varying(9) NOT NULL,
    type character varying(10) NOT NULL,
    content text NOT NULL,
    caption text DEFAULT ''::text NOT NULL,
    lat double precision NOT NULL,
    lng double precision NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL
);


--
-- Name: supports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.supports (
    post_id uuid NOT NULL,
    user_id character varying(9) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id character varying(9) NOT NULL,
    nickname character varying(32) NOT NULL,
    identity_pubkey text NOT NULL,
    recovery_hash text NOT NULL,
    discoverable_by character varying(10) DEFAULT 'nickname'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pass_hash text,
    last_seen timestamp with time zone,
    avatar_url text,
    district_id integer
);


--
-- Name: vessel_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vessel_members (
    vessel_id uuid NOT NULL,
    user_id character varying(9) NOT NULL,
    role character varying(10) DEFAULT 'member'::character varying NOT NULL,
    joined_at timestamp with time zone DEFAULT now() NOT NULL,
    last_read_at timestamp with time zone DEFAULT now() NOT NULL,
    muted boolean DEFAULT false NOT NULL
);


--
-- Name: vessels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vessels (
    id uuid NOT NULL,
    name character varying(60) NOT NULL,
    topic character varying(60) NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    owner_id character varying(9) NOT NULL,
    cover_url text,
    is_public boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    kind character varying(12) DEFAULT 'general'::character varying NOT NULL,
    district_id integer,
    business_id uuid,
    lat double precision,
    lng double precision
);


--
-- Name: districts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.districts ALTER COLUMN id SET DEFAULT nextval('public.districts_id_seq'::regclass);


--
-- Name: blocks blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocks
    ADD CONSTRAINT blocks_pkey PRIMARY KEY (blocker_id, blocked_id);


--
-- Name: businesses businesses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.businesses
    ADD CONSTRAINT businesses_pkey PRIMARY KEY (id);


--
-- Name: comments comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_pkey PRIMARY KEY (id);


--
-- Name: contacts contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contacts
    ADD CONSTRAINT contacts_pkey PRIMARY KEY (owner_id, contact_id);


--
-- Name: districts districts_osm_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.districts
    ADD CONSTRAINT districts_osm_id_key UNIQUE (osm_id);


--
-- Name: districts districts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.districts
    ADD CONSTRAINT districts_pkey PRIMARY KEY (id);


--
-- Name: mailbox mailbox_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mailbox
    ADD CONSTRAINT mailbox_pkey PRIMARY KEY (id);


--
-- Name: map_pins map_pins_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_pins
    ADD CONSTRAINT map_pins_pkey PRIMARY KEY (id);


--
-- Name: map_presence map_presence_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_presence
    ADD CONSTRAINT map_presence_pkey PRIMARY KEY (user_id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: posts posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (user_id);


--
-- Name: push_subscriptions push_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_pkey PRIMARY KEY (endpoint);


--
-- Name: reports reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_pkey PRIMARY KEY (id);


--
-- Name: request_ignores request_ignores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_ignores
    ADD CONSTRAINT request_ignores_pkey PRIMARY KEY (user_id, peer_id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (token);


--
-- Name: stories stories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stories
    ADD CONSTRAINT stories_pkey PRIMARY KEY (id);


--
-- Name: supports supports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supports
    ADD CONSTRAINT supports_pkey PRIMARY KEY (post_id, user_id);


--
-- Name: users users_nickname_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_nickname_key UNIQUE (nickname);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: vessel_members vessel_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vessel_members
    ADD CONSTRAINT vessel_members_pkey PRIMARY KEY (vessel_id, user_id);


--
-- Name: vessels vessels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vessels
    ADD CONSTRAINT vessels_pkey PRIMARY KEY (id);


--
-- Name: idx_comments_post; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comments_post ON public.comments USING btree (post_id, created_at);


--
-- Name: idx_map_pins_geo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_map_pins_geo ON public.map_pins USING btree (lat, lng);


--
-- Name: idx_mb; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mb ON public.mailbox USING btree (recipient_id);


--
-- Name: idx_msg_a; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_msg_a ON public.messages USING btree (sender_id, recipient_id);


--
-- Name: idx_msg_sent_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_msg_sent_at ON public.messages USING btree (sent_at);


--
-- Name: idx_msg_unread; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_msg_unread ON public.messages USING btree (recipient_id, sender_id) WHERE (read_at IS NULL);


--
-- Name: idx_posts_vessel; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_posts_vessel ON public.posts USING btree (vessel_id, created_at DESC);


--
-- Name: idx_stories_expires; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_stories_expires ON public.stories USING btree (expires_at);


--
-- Name: blocks blocks_blocked_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocks
    ADD CONSTRAINT blocks_blocked_id_fkey FOREIGN KEY (blocked_id) REFERENCES public.users(id);


--
-- Name: blocks blocks_blocker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocks
    ADD CONSTRAINT blocks_blocker_id_fkey FOREIGN KEY (blocker_id) REFERENCES public.users(id);


--
-- Name: businesses businesses_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.businesses
    ADD CONSTRAINT businesses_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id);


--
-- Name: businesses businesses_vessel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.businesses
    ADD CONSTRAINT businesses_vessel_id_fkey FOREIGN KEY (vessel_id) REFERENCES public.vessels(id);


--
-- Name: comments comments_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.users(id);


--
-- Name: comments comments_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: districts districts_vessel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.districts
    ADD CONSTRAINT districts_vessel_id_fkey FOREIGN KEY (vessel_id) REFERENCES public.vessels(id);


--
-- Name: mailbox mailbox_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mailbox
    ADD CONSTRAINT mailbox_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES public.users(id);


--
-- Name: map_pins map_pins_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_pins
    ADD CONSTRAINT map_pins_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: map_presence map_presence_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_presence
    ADD CONSTRAINT map_presence_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: posts posts_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.users(id);


--
-- Name: posts posts_vessel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_vessel_id_fkey FOREIGN KEY (vessel_id) REFERENCES public.vessels(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: push_subscriptions push_subscriptions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_subscriptions
    ADD CONSTRAINT push_subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: reports reports_reported_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_reported_id_fkey FOREIGN KEY (reported_id) REFERENCES public.users(id);


--
-- Name: reports reports_reporter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES public.users(id);


--
-- Name: request_ignores request_ignores_peer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_ignores
    ADD CONSTRAINT request_ignores_peer_id_fkey FOREIGN KEY (peer_id) REFERENCES public.users(id);


--
-- Name: request_ignores request_ignores_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_ignores
    ADD CONSTRAINT request_ignores_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: sessions sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: stories stories_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stories
    ADD CONSTRAINT stories_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: supports supports_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supports
    ADD CONSTRAINT supports_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: supports supports_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supports
    ADD CONSTRAINT supports_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: vessel_members vessel_members_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vessel_members
    ADD CONSTRAINT vessel_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: vessel_members vessel_members_vessel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vessel_members
    ADD CONSTRAINT vessel_members_vessel_id_fkey FOREIGN KEY (vessel_id) REFERENCES public.vessels(id) ON DELETE CASCADE;


--
-- Name: vessels vessels_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vessels
    ADD CONSTRAINT vessels_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

\unrestrict vwnjOLMufZFL4VHgIEUAHLFJhpYX1cHuMh7G8nNolMAdkvzuFWWRc2ozbIGdM6T

