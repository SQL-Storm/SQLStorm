-- {"query": "8036.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3362} 
with recent_posts as (
    select
        p.id,
        p.posttypeid,
        p.creationdate,
        p.owneruserid,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.parentid
    from posts p
    where p.creationdate >= now() - interval '365 days'
),
user_activity as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate as user_created,
        u.location,
        coalesce(u.websiteurl, '') as websiteurl,
        u.upvotes,
        u.downvotes,
        u.views as profile_views,
        count(distinct p.id) filter (where p.posttypeid in (1,2)) as total_posts,
        count(distinct case when p.posttypeid = 1 then p.id end) as total_questions,
        count(distinct case when p.posttypeid = 2 then p.id end) as total_answers,
        count(distinct c.id) as total_comments,
        count(distinct b.id) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges
    from users u
    left join posts p on p.owneruserid = u.id
    left join comments c on c.userid = u.id
    left join badges b on b.userid = u.id
    group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.websiteurl, u.upvotes, u.downvotes, u.views
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        min(v.creationdate) as first_vote_at,
        max(v.creationdate) as last_vote_at
    from votes v
    group by v.postid
),
postlinks_agg as (
    select
        pl.postid,
        sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
        sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_of_count,
        count(*) as total_links
    from postlinks pl
    group by pl.postid
),
tag_stats as (
    select
        t.tagname,
        t.count as tag_total_count,
        t.ismoderatoronly,
        t.isrequired,
        coalesce(ep.title, '') as excerpt_title,
        coalesce(wp.title, '') as wiki_title
    from tags t
    left join posts ep on ep.id = t.excerptpostid
    left join posts wp on wp.id = t.wikipostid
),
question_core as (
    select
        q.id as question_id,
        q.creationdate as question_created,
        q.owneruserid as asker_id,
        q.score as question_score,
        q.viewcount as question_views,
        q.title as question_title,
        q.tags,
        qa.id as accepted_answer_id,
        qa.owneruserid as accepted_answerer_id,
        qa.score as accepted_answer_score,
        qa.creationdate as accepted_answer_created,
        va.upvotes as q_up,
        va.downvotes as q_down,
        va.first_vote_at as q_first_vote_at,
        va.last_vote_at as q_last_vote_at,
        pla.linked_count,
        pla.duplicate_of_count
    from recent_posts q
    left join posts qa on qa.id = q.acceptedanswerid
    left join votes_agg va on va.postid = q.id
    left join postlinks_agg pla on pla.postid = q.id
    where q.posttypeid = 1
),
answer_agg as (
    select
        a.parentid as question_id,
        count(*) as answer_count,
        max(a.score) as max_answer_score,
        avg(a.score::numeric) as avg_answer_score,
        min(a.creationdate) as first_answer_at,
        max(a.creationdate) as last_answer_at,
        count(*) filter (where a.owneruserid is null) as anon_answers
    from recent_posts a
    where a.posttypeid = 2
    group by a.parentid
),
comment_agg as (
    select
        c.postid,
        count(*) as comment_count,
        max(c.score) as max_comment_score,
        avg(c.score::numeric) as avg_comment_score,
        min(c.creationdate) as first_comment_at,
        max(c.creationdate) as last_comment_at
    from comments c
    group by c.postid
),
history_flags as (
    select
        ph.postid,
        bool_or(ph.posthistorytypeid = 10) as was_closed,
        bool_or(ph.posthistorytypeid = 11) as was_reopened,
        bool_or(ph.posthistorytypeid = 12) as was_deleted,
        bool_or(ph.posthistorytypeid = 13) as was_undeleted,
        bool_or(ph.posthistorytypeid = 19) as was_protected,
        bool_or(ph.posthistorytypeid = 50) as was_community_bump,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as last_edit_at
    from posthistory ph
    group by ph.postid
),
tag_expanded as (
    select
        qc.question_id,
        unnest(string_to_array(substring(qc.tags, 2, length(qc.tags)-2), '><')) as tagname
    from question_core qc
    where qc.tags is not null and length(qc.tags) > 2
),
tag_enriched as (
    select
        te.question_id,
        te.tagname,
        ts.tag_total_count,
        ts.ismoderatoronly,
        ts.isrequired
    from tag_expanded te
    left join tag_stats ts on lower(ts.tagname) = lower(te.tagname)
),
tag_rollup as (
    select
        question_id,
        count(*) as tag_count,
        sum(case when ismoderatoronly then 1 else 0 end) as moderator_only_tags,
        sum(case when isrequired then 1 else 0 end) as required_tags,
        max(tag_total_count) as max_tag_popularity,
        min(tag_total_count) as min_tag_popularity,
        string_agg(tagname, ',' order by tagname) as tag_list
    from tag_enriched
    group by question_id
),
hotness as (
    select
        qc.question_id,
        (
            coalesce(qc.question_score,0) * 1.5
            + coalesce(va.upvotes,0) * 1.2
            - coalesce(va.downvotes,0) * 0.8
            + coalesce(aa.answer_count,0) * 2.0
            + least(greatest(10000 - extract(epoch from (now() - qc.question_created))/60, 0), 10000) / 500.0
            + coalesce(ca.comment_count,0) * 0.5
            + coalesce(qc.question_views,0) / 200.0
            + case when qc.accepted_answer_id is not null then 5 else 0 end
            - case when hf.was_closed then 10 else 0 end
        ) as hot_score
    from question_core qc
    left join votes_agg va on va.postid = qc.question_id
    left join answer_agg aa on aa.question_id = qc.question_id
    left join comment_agg ca on ca.postid = qc.question_id
    left join history_flags hf on hf.postid = qc.question_id
),
user_quality as (
    select
        ua.user_id,
        case
            when ua.total_posts = 0 then null
            else round((ua.upvotes - ua.downvotes)::numeric / nullif(ua.total_posts,0), 3)
        end as net_votes_per_post,
        case
            when ua.total_answers = 0 then null
            else round((ua.total_answers::numeric / nullif(ua.total_posts,0)) * 100, 2)
        end as answer_ratio_pct,
        round((coalesce(ua.gold_badges,0)*5 + coalesce(ua.silver_badges,0)*2 + coalesce(ua.bronze_badges,0)*1)::numeric, 2) as badge_score
    from user_activity ua
),
ranked_questions as (
    select
        qc.question_id,
        qc.question_created,
        qc.asker_id,
        qc.question_score,
        qc.question_views,
        qc.question_title,
        tr.tag_count,
        tr.tag_list,
        aa.answer_count,
        ca.comment_count,
        hf.was_closed,
        hf.was_reopened,
        hf.was_deleted,
        hf.was_undeleted,
        hf.was_protected,
        hf.was_community_bump,
        hot.hot_score,
        row_number() over (order by hot.hot_score desc nulls last, qc.question_created desc) as rn_hot,
        row_number() over (order by qc.question_views desc nulls last) as rn_views,
        row_number() over (order by qc.question_score desc nulls last) as rn_score,
        dense_rank() over (order by coalesce(aa.answer_count,0) desc) as dr_answers
    from question_core qc
    left join tag_rollup tr on tr.question_id = qc.question_id
    left join answer_agg aa on aa.question_id = qc.question_id
    left join comment_agg ca on ca.postid = qc.question_id
    left join history_flags hf on hf.postid = qc.question_id
    left join hotness hot on hot.question_id = qc.question_id
),
question_health as (
    select
        rq.question_id,
        case
            when rq.was_deleted then 'deleted'
            when rq.was_closed and rq.was_reopened then 'reopened'
            when rq.was_closed then 'closed'
            else 'open'
        end as lifecycle_status,
        case
            when rq.tag_count is null or rq.tag_count = 0 then 'untagged'
            when rq.tag_count = 1 then 'single-tag'
            when rq.tag_count between 2 and 4 then 'multi-tag'
            else 'over-tagged'
        end as tagging_state,
        case
            when rq.answer_count is null or rq.answer_count = 0 then 'unanswered'
            when rq.answer_count = 1 then 'single-answer'
            when rq.answer_count <= 5 then 'few-answers'
            else 'many-answers'
        end as answer_state
    from ranked_questions rq
),
accepted_answer_latency as (
    select
        qc.question_id,
        extract(epoch from (qa.creationdate - qc.question_created)) / 3600.0 as hours_to_accept
    from question_core qc
    left join posts qa on qa.id = qc.accepted_answer_id
),
top_dupe_targets as (
    select
        pl.relatedpostid as target_question_id,
        count(*) as dupes_count
    from postlinks pl
    join posts p on p.id = pl.postid and p.posttypeid = 1
    where pl.linktypeid = 3
    group by pl.relatedpostid
),
final as (
    select
        rq.question_id,
        rq.question_created,
        rq.asker_id,
        au.displayname as asker_name,
        au.reputation as asker_rep,
        uq.net_votes_per_post,
        uq.answer_ratio_pct,
        uq.badge_score,
        rq.question_score,
        rq.question_views,
        rq.question_title,
        rq.tag_list,
        rq.tag_count,
        rq.rn_hot,
        rq.rn_views,
        rq.rn_score,
        rq.dr_answers,
        qh.lifecycle_status,
        qh.tagging_state,
        qh.answer_state,
        coalesce(aa.answer_count,0) as answer_count,
        coalesce(ca.comment_count,0) as comment_count,
        coalesce(hot.hot_score, 0) as hot_score,
        aal.hours_to_accept,
        tdt.dupes_count as duplicate_target_for,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(pla.linked_count,0) as linked_count,
        coalesce(pla.duplicate_of_count,0) as duplicate_of_count,
        hf.last_edit_at,
        hf.last_closed_at,
        hf.last_reopened_at
    from ranked_questions rq
    left join user_activity au on au.user_id = rq.asker_id
    left join user_quality uq on uq.user_id = rq.asker_id
    left join answer_agg aa on aa.question_id = rq.question_id
    left join comment_agg ca on ca.postid = rq.question_id
    left join history_flags hf on hf.postid = rq.question_id
    left join hotness hot on hot.question_id = rq.question_id
    left join accepted_answer_latency aal on aal.question_id = rq.question_id
    left join top_dupe_targets tdt on tdt.target_question_id = rq.question_id
    left join votes_agg va on va.postid = rq.question_id
    left join postlinks_agg pla on pla.postid = rq.question_id
)
select
    f.question_id,
    f.question_created,
    f.asker_id,
    coalesce(nullif(trim(f.asker_name), ''), '(unknown)') as asker_name,
    f.asker_rep,
    f.net_votes_per_post,
    f.answer_ratio_pct,
    f.badge_score,
    f.question_score,
    f.question_views,
    left(coalesce(f.question_title,''), 200) as question_title,
    f.tag_list,
    f.tag_count,
    f.lifecycle_status,
    f.tagging_state,
    f.answer_state,
    f.answer_count,
    f.comment_count,
    f.upvotes,
    f.downvotes,
    f.linked_count,
    f.duplicate_of_count,
    round(f.hot_score::numeric, 3) as hot_score,
    round(f.hours_to_accept::numeric, 2) as hours_to_accept,
    f.duplicate_target_for,
    f.rn_hot,
    f.rn_views,
    f.rn_score,
    f.dr_answers
from final f
where
    coalesce(f.asker_rep, 0) >= 1
    and (f.lifecycle_status <> 'deleted' or f.question_created >= now() - interval '7 days')
    and (f.tag_count is null or f.tag_count <= 10)
    and (
        f.hot_score >= (
            select percentile_disc(0.9) within group (order by hot_score)
            from final
        )
        or f.rn_views <= 100
        or f.rn_score <= 100
    )
order by f.rn_hot, f.rn_views, f.question_created desc
limit 500;