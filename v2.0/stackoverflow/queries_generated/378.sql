-- {"query": "378.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3198} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown') as domain,
           row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
),
questions as (
    select p.id as qid,
           p.owneruserid as asker_id,
           p.creationdate as q_created,
           p.score as q_score,
           p.viewcount,
           p.title,
           p.tags,
           p.acceptedanswerid,
           p.closeddate,
           (p.closeddate is not null)::int as is_closed
    from posts p
    where p.posttypeid = 1
),
answers as (
    select a.id as aid,
           a.parentid as qid,
           a.owneruserid as answerer_id,
           a.creationdate as a_created,
           a.score as a_score
    from posts a
    where a.posttypeid = 2
),
accepted as (
    select q.qid,
           q.acceptedanswerid as aid
    from questions q
    where q.acceptedanswerid is not null
),
qa_stats as (
    select
        q.qid,
        q.asker_id,
        count(a.aid) as answer_count,
        sum(case when a.aid = q.acceptedanswerid then 1 else 0 end) as has_accepted,
        min(a.a_created) filter (where a.aid <> q.acceptedanswerid or q.acceptedanswerid is null) as first_nonaccepted_time,
        min(a.a_created) as first_answer_time,
        max(a.a_created) as last_answer_time,
        avg(a.a_score) as avg_answer_score
    from questions q
    left join answers a on a.qid = q.qid
    group by q.qid, q.asker_id
),
vote_agg as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
    from votes v
    group by v.postid
),
comment_agg as (
    select c.postid,
           count(*) as comment_count,
           max(c.creationdate) as last_comment_at,
           sum(case when c.score > 0 then 1 else 0 end) as pos_comments
    from comments c
    group by c.postid
),
dup_links as (
    select pl.postid as qid,
           count(*) filter (where pl.linktypeid = 3) as duplicate_count,
           count(*) filter (where pl.linktypeid = 1) as linked_count
    from postlinks pl
    group by pl.postid
),
tag_split as (
    select
        q.qid,
        unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tag
    from questions q
    where q.tags is not null and q.tags like '<%>'
),
top_tags as (
    select ts.qid,
           string_agg(ts.tag, ',' order by ts.tag) as tag_list,
           count(*) as tag_count
    from tag_split ts
    group by ts.qid
),
post_history_flags as (
    select ph.postid as qid,
           max(case when ph.posthistorytypeid = 10 then 1 else 0 end) as ever_closed,
           max(case when ph.posthistorytypeid = 11 then 1 else 0 end) as ever_reopened,
           max(case when ph.posthistorytypeid = 52 then 1 else 0 end) as became_hot,
           max(case when ph.posthistorytypeid = 53 then 1 else 0 end) as removed_hot
    from posthistory ph
    group by ph.postid
),
asker_activity as (
    select
        u.id as user_id,
        count(distinct p.id) filter (where p.posttypeid = 1) as total_questions,
        count(distinct p.id) filter (where p.posttypeid = 2) as total_answers,
        sum(coalesce(p.score,0)) as total_post_score,
        max(p.lastactivitydate) as last_activity
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
badge_summary as (
    select b.userid as user_id,
           sum(case when b.class = 1 then 1 else 0 end) as gold,
           sum(case when b.class = 2 then 1 else 0 end) as silver,
           sum(case when b.class = 3 then 1 else 0 end) as bronze,
           sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
    from badges b
    group by b.userid
),
question_window as (
    select
        q.qid,
        q.asker_id,
        q.q_created,
        q.q_score,
        q.viewcount,
        q.title,
        tt.tag_list,
        tt.tag_count,
        qa.answer_count,
        qa.has_accepted,
        va.upvotes,
        va.downvotes,
        va.favorites,
        va.bounty_started,
        va.bounty_awarded,
        ca.comment_count,
        ca.last_comment_at,
        dl.duplicate_count,
        dl.linked_count,
        phf.ever_closed,
        phf.ever_reopened,
        phf.became_hot,
        phf.removed_hot,
        row_number() over (partition by q.asker_id order by coalesce(q.viewcount,0) desc, q.q_score desc, q.q_created desc) as rn_by_asker,
        ntile(5) over (order by coalesce(q.viewcount,0) desc nulls last) as view_ntile,
        dense_rank() over (order by q.q_score desc) as score_rank
    from questions q
    left join qa_stats qa on qa.qid = q.qid
    left join vote_agg va on va.postid = q.qid
    left join comment_agg ca on ca.postid = q.qid
    left join dup_links dl on dl.qid = q.qid
    left join top_tags tt on tt.qid = q.qid
    left join post_history_flags phf on phf.qid = q.qid
),
distinct_domains as (
    select domain, count(*) as cnt
    from recent_users
    group by domain
    having count(*) > 5
),
user_enriched as (
    select
        u.user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        u.domain,
        ad.total_questions,
        ad.total_answers,
        ad.total_post_score,
        ad.last_activity,
        bs.gold,
        bs.silver,
        bs.bronze,
        bs.tag_badges,
        (coalesce(bs.gold,0)*100 + coalesce(bs.silver,0)*10 + coalesce(bs.bronze,0)) as badge_score,
        case
            when u.reputation >= 100000 then 'legend'
            when u.reputation >= 25000 then 'expert'
            when u.reputation >= 5000 then 'pro'
            when u.reputation >= 1000 then 'intermediate'
            else 'beginner'
        end as rep_band
    from recent_users u
    left join asker_activity ad on ad.user_id = u.user_id
    left join badge_summary bs on bs.user_id = u.user_id
    where u.rn <= 10000
),
domain_rank as (
    select
        ue.*,
        rank() over (partition by ue.domain order by ue.reputation desc, ue.user_id) as rank_in_domain
    from user_enriched ue
    where ue.domain in (select domain from distinct_domains)
),
-- compute rolling aggregates over questions by asker
asker_q_rolling as (
    select
        qw.asker_id,
        qw.qid,
        qw.q_created,
        sum(coalesce(qw.q_score,0)) over (partition by qw.asker_id order by qw.q_created rows between unbounded preceding and current row) as cum_score_by_asker,
        avg(coalesce(qw.viewcount,0)) over (partition by qw.asker_id order by qw.q_created rows between 10 preceding and current row) as avg_views_last_10,
        count(*) over (partition by qw.asker_id) as total_q_by_asker
    from question_window qw
),
-- complex predicate and null logic for filtering "interesting" questions
interesting_questions as (
    select
        qw.qid,
        qw.asker_id,
        qw.q_created,
        qw.q_score,
        qw.viewcount,
        qw.title,
        qw.tag_list,
        qw.tag_count,
        qw.answer_count,
        qw.has_accepted,
        qw.upvotes,
        qw.downvotes,
        qw.favorites,
        qw.bounty_started,
        qw.bounty_awarded,
        qw.comment_count,
        qw.last_comment_at,
        qw.duplicate_count,
        qw.linked_count,
        qw.ever_closed,
        qw.ever_reopened,
        qw.became_hot,
        qw.removed_hot,
        aq.cum_score_by_asker,
        aq.avg_views_last_10,
        aq.total_q_by_asker,
        (coalesce(qw.upvotes,0) - coalesce(qw.downvotes,0)) as net_votes,
        case when qw.has_accepted = 1 then 1 else 0 end as accepted_flag
    from question_window qw
    join asker_q_rolling aq on aq.qid = qw.qid
    where
        (
            -- high engagement or controversy
            coalesce(qw.viewcount,0) >= 1000
            or coalesce(qw.comment_count,0) >= 10
            or (coalesce(qw.upvotes,0) >= 10 and coalesce(qw.downvotes,0) >= 5)
        )
        and (
            -- include either hot questions or reopened ones, but exclude those removed from hot unless they also have bounty
            (coalesce(qw.became_hot,0) = 1 and coalesce(qw.removed_hot,0) = 0)
            or (coalesce(qw.ever_reopened,0) = 1)
            or (coalesce(qw.bounty_started,0) > 0)
        )
        and not (coalesce(qw.duplicate_count,0) > 3 and coalesce(qw.has_accepted,0) = 0)
),
-- per-domain, per-rep_band aggregates on interesting questions
domain_band_stats as (
    select
        dr.domain,
        ue.rep_band,
        count(distinct iq.qid) as iq_count,
        avg(iq.net_votes) as avg_net_votes,
        sum(iq.accepted_flag) as accepted_count,
        percentile_cont(0.9) within group (order by coalesce(iq.viewcount,0)) as p90_views
    from domain_rank dr
    join interesting_questions iq on iq.asker_id = dr.user_id
    join user_enriched ue on ue.user_id = dr.user_id
    group by dr.domain, ue.rep_band
),
-- pick top N interesting questions per domain by a composite score
scored_iq as (
    select
        iq.*,
        dr.domain,
        ue.displayname,
        ue.reputation,
        ue.badge_score,
        (
            0.5 * least(coalesce(iq.viewcount,0), 100000) / 100000.0 +
            0.3 * greatest(iq.net_votes, 0) / greatest(iq.net_votes + coalesce(iq.downvotes,0) + 1, 1)::float +
            0.1 * coalesce(iq.answer_count,0) / greatest(iq.answer_count + 5, 1)::float +
            0.1 * least(coalesce(ue.badge_score,0), 1000) / 1000.0
        ) as composite_score
    from interesting_questions iq
    join domain_rank dr on dr.user_id = iq.asker_id
    join user_enriched ue on ue.user_id = iq.asker_id
),
top_scored_per_domain as (
    select
        s.*,
        row_number() over (partition by s.domain order by s.composite_score desc, s.q_created desc, s.qid desc) as rn_dom
    from scored_iq s
),
-- correlate tags back to Tags table for global tag popularity and moderation flags
tag_enrichment as (
    select
        ts.qid,
        avg(t.count) as avg_tag_popularity,
        max(case when t.ismoderaToronly = 1 then 1 else 0 end) as has_mod_only,
        max(case when t.isrequired = 1 then 1 else 0 end) as has_required
    from tag_split ts
    left join tags t on lower(t.tagname) = lower(ts.tag)
    group by ts.qid
),
-- final assembly
final as (
    select
        td.domain,
        td.qid,
        td.title,
        td.tag_list,
        te.avg_tag_popularity,
        te.has_mod_only,
        te.has_required,
        td.displayname as asker_name,
        td.reputation as asker_rep,
        td.badge_score,
        td.q_created,
        td.viewcount,
        td.q_score,
        td.net_votes,
        td.answer_count,
        td.has_accepted,
        td.comment_count,
        td.duplicate_count,
        td.ever_closed,
        td.ever_reopened,
        td.became_hot,
        td.removed_hot,
        td.composite_score,
        dbs.rep_band,
        dbs.iq_count as domain_band_iq_count,
        dbs.avg_net_votes as domain_band_avg_net_votes,
        dbs.p90_views as domain_band_p90_views
    from top_scored_per_domain td
    left join tag_enrichment te on te.qid = td.qid
    left join user_enriched ue on ue.user_id = td.asker_id
    left join domain_band_stats dbs on dbs.domain = td.domain and dbs.rep_band = ue.rep_band
    where td.rn_dom <= 5
)
select *
from final
order by composite_score desc, q_created desc, qid desc;