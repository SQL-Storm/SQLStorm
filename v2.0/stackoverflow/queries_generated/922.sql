-- {"query": "922.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3559} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.location,
        u.creationdate,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (partition by coalesce(nullif(trim(u.location), ''), 'Unknown') order by u.reputation desc, u.id) as loc_rep_rank
    from users u
    where u.creationdate >= (select date_trunc('year', max(creationdate)) from users)
),
question_posts as (
    select
        p.id as qid,
        p.owneruserid as q_ownerid,
        p.creationdate as q_created,
        p.score as q_score,
        p.viewcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.closeddate,
        p.favoritecount,
        p.commentcount,
        p.answercount,
        coalesce(p.ownerdisplayname, 'Anonymous') as q_ownername
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select
        a.id as aid,
        a.parentid as qid,
        a.owneruserid as a_ownerid,
        a.creationdate as a_created,
        a.score as a_score
    from posts a
    where a.posttypeid = 2
),
tag_explode as (
    select
        q.qid,
        unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tag
    from question_posts q
    where q.tags is not null
),
tag_stats as (
    select
        t.tag,
        count(*) as tag_q_count,
        avg(q.q_score)::numeric(18,4) as avg_q_score,
        sum(q.viewcount) as total_views
    from tag_explode t
    join question_posts q on q.qid = t.qid
    group by t.tag
),
accepted_answer_lag as (
    select
        q.qid,
        q.q_ownerid,
        q.q_created,
        q.acceptedanswerid,
        a.aid,
        a.a_ownerid,
        a.a_created,
        extract(epoch from (a.a_created - q.q_created)) as seconds_to_accept
    from question_posts q
    left join answer_posts a
      on a.aid = q.acceptedanswerid
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
        max(v.creationdate) as last_vote_at
    from votes v
    group by v.postid
),
comment_sentiment as (
    select
        c.postid,
        avg(case when c.text ilike any(array['%thanks%','%great%','%helpful%']) then 1 when c.text ilike any(array['%bad%','%terrible%','%useless%']) then -1 else 0 end)::numeric(18,4) as sentiment_score,
        count(*) as comment_count
    from comments c
    group by c.postid
),
user_badge_rank as (
    select
        b.userid,
        count(*) filter (where b.class = 1) as golds,
        count(*) filter (where b.class = 2) as silvers,
        count(*) filter (where b.class = 3) as bronzes,
        dense_rank() over (order by count(*) filter (where b.class = 1) desc, count(*) filter (where b.class = 2) desc, count(*) filter (where b.class = 3) desc, min(b.date)) as badge_rank
    from badges b
    group by b.userid
),
post_history_flags as (
    select
        ph.postid,
        bool_or(ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)) as mod_actions_present,
        max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as closed_at,
        max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as reopened_at,
        count(*) filter (where ph.posthistorytypeid in (24)) as suggested_edits_applied,
        count(*) filter (where ph.posthistorytypeid in (33,34)) as notices_count
    from posthistory ph
    group by ph.postid
),
dup_links as (
    select
        pl.postid as dup_postid,
        pl.relatedpostid as original_qid,
        count(*) as dup_link_count,
        max(pl.creationdate) as dup_last_at
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
q_activity as (
    select
        q.qid,
        q.q_ownerid,
        coalesce(v.upvotes,0) - coalesce(v.downvotes,0) as net_votes,
        coalesce(v.favorites,0) as favorite_votes,
        coalesce(v.bounty_total,0) as bounty_total,
        coalesce(cs.sentiment_score,0) as avg_comment_sentiment,
        coalesce(cs.comment_count,0) as total_comments,
        v.last_vote_at,
        ph.mod_actions_present,
        ph.closed_at,
        ph.reopened_at,
        ph.suggested_edits_applied,
        ph.notices_count
    from question_posts q
    left join votes_agg v on v.postid = q.qid
    left join comment_sentiment cs on cs.postid = q.qid
    left join post_history_flags ph on ph.postid = q.qid
),
q_quality as (
    select
        q.qid,
        q.title,
        q.viewcount,
        q.q_score,
        q.favoritecount,
        qa.net_votes,
        qa.favorite_votes,
        qa.bounty_total,
        qa.avg_comment_sentiment,
        qa.total_comments,
        qa.closed_at,
        qa.reopened_at,
        qa.suggested_edits_applied,
        qa.notices_count,
        aal.seconds_to_accept,
        percentile_disc(0.5) within group (order by aal.seconds_to_accept) over () as global_median_accept_secs,
        row_number() over (order by coalesce(qa.net_votes,0) desc, coalesce(q.viewcount,0) desc, q.qid) as popularity_rank
    from question_posts q
    left join q_activity qa on qa.qid = q.qid
    left join accepted_answer_lag aal on aal.qid = q.qid
),
user_activity as (
    select
        u.id as user_id,
        count(*) filter (where p.posttypeid = 1) as questions_posted,
        count(*) filter (where p.posttypeid = 2) as answers_posted,
        avg(p.score)::numeric(18,4) as avg_post_score,
        max(p.lastactivitydate) as last_post_activity,
        sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as total_question_views,
        count(distinct case when p.posttypeid = 1 then p.id end) filter (where p.closeddate is not null) as closed_questions
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
cohort_metrics as (
    select
        ru.cohort_month,
        count(distinct ru.user_id) as users_in_cohort,
        avg(ru.reputation)::numeric(18,2) as avg_rep_cohort,
        sum(ua.questions_posted) as cohort_questions,
        sum(ua.answers_posted) as cohort_answers,
        avg(nullif(ua.avg_post_score,0)) filter (where ua.avg_post_score is not null)::numeric(18,4) as avg_post_score_cohort
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    group by ru.cohort_month
),
top_tag_per_user as (
    select
        q.owneruserid as user_id,
        t.tag,
        count(*) as cnt,
        row_number() over (partition by q.owneruserid order by count(*) desc, min(q.id)) as rn
    from posts q
    join tag_explode t on t.qid = q.id
    where q.posttypeid = 1
    group by q.owneruserid, t.tag
),
user_enriched as (
    select
        u.id as user_id,
        u.displayname,
        coalesce(nullif(trim(u.location), ''), 'Unknown') as location,
        u.reputation,
        ua.questions_posted,
        ua.answers_posted,
        ua.avg_post_score,
        ua.total_question_views,
        ua.closed_questions,
        ubr.golds, ubr.silvers, ubr.bronzes, ubr.badge_rank,
        tt.tag as favorite_tag
    from users u
    left join user_activity ua on ua.user_id = u.id
    left join user_badge_rank ubr on ubr.userid = u.id
    left join top_tag_per_user tt on tt.user_id = u.id and tt.rn = 1
),
question_with_tags as (
    select
        q.qid,
        lower(coalesce(t.tag, 'untagged')) as tag
    from question_posts q
    left join tag_explode t on t.qid = q.qid
),
tag_window as (
    select
        qwt.tag,
        qwt.qid,
        row_number() over (partition by qwt.tag order by qwt.qid) as rn,
        count(*) over (partition by qwt.tag) as tag_q_total
    from question_with_tags qwt
),
tag_coverage as (
    select
        tw.tag,
        sum(case when tw.rn % 2 = 0 then 1 else 0 end) as even_ranked_questions,
        max(tw.tag_q_total) as tag_q_total
    from tag_window tw
    group by tw.tag
),
final_union as (
    select
        q.qid::text as entity_id,
        'question' as entity_type,
        q.title as label,
        q.viewcount,
        q.q_score as metric_a,
        coalesce(q.net_votes,0) as metric_b,
        coalesce(q.favorite_votes,0) as metric_c,
        coalesce(q.seconds_to_accept, -1) as metric_d,
        coalesce(q.avg_comment_sentiment,0) as metric_e,
        q.popularity_rank as rank_primary,
        null::int as rank_secondary,
        coalesce(q.closed_at, q.reopened_at) as event_ts,
        null::varchar(100) as category,
        null::varchar(35) as tag,
        null::int as user_id_ref
    from q_quality q

    union all

    select
        u.user_id::text as entity_id,
        'user' as entity_type,
        u.displayname as label,
        coalesce(u.total_question_views,0) as viewcount,
        coalesce(u.questions_posted,0) as metric_a,
        coalesce(u.answers_posted,0) as metric_b,
        coalesce(u.avg_post_score,0)::int as metric_c,
        coalesce(u.reputation,0) as metric_d,
        coalesce(u.golds,0) + coalesce(u.silvers,0) + coalesce(u.bronzes,0) as metric_e,
        u.badge_rank as rank_primary,
        null::int as rank_secondary,
        null::timestamp as event_ts,
        u.location as category,
        u.favorite_tag as tag,
        u.user_id as user_id_ref
    from user_enriched u

    union all

    select
        to_char(cm.cohort_month, 'YYYY-MM') as entity_id,
        'cohort' as entity_type,
        'Cohort ' || to_char(cm.cohort_month, 'Mon YYYY') as label,
        cm.users_in_cohort as viewcount,
        cm.cohort_questions as metric_a,
        cm.cohort_answers as metric_b,
        coalesce(cm.avg_post_score_cohort,0)::int as metric_c,
        cm.avg_rep_cohort::int as metric_d,
        (cm.cohort_questions + cm.cohort_answers) as metric_e,
        dense_rank() over (order by cm.cohort_month) as rank_primary,
        null::int as rank_secondary,
        cm.cohort_month as event_ts,
        null::varchar(100) as category,
        null::varchar(35) as tag,
        null::int as user_id_ref
    from cohort_metrics cm

    union all

    select
        tc.tag as entity_id,
        'tag' as entity_type,
        'Tag ' || tc.tag as label,
        tc.tag_q_total as viewcount,
        ts.tag_q_count as metric_a,
        ts.total_views as metric_b,
        (ts.avg_q_score * 100)::int as metric_c,
        tc.even_ranked_questions as metric_d,
        (ts.tag_q_count - coalesce(tc.even_ranked_questions,0)) as metric_e,
        dense_rank() over (order by ts.total_views desc nulls last) as rank_primary,
        dense_rank() over (order by ts.tag_q_count desc nulls last) as rank_secondary,
        null::timestamp as event_ts,
        null::varchar(100) as category,
        ts.tag as tag,
        null::int as user_id_ref
    from tag_coverage tc
    left join tag_stats ts on ts.tag = tc.tag
)
select
    fu.*,
    -- correlated subquery for duplicate linkage presence
    exists (
        select 1
        from dup_links dl
        where fu.entity_type = 'question'
          and dl.dup_postid = fu.entity_id::int
          and dl.dup_last_at >= now() - interval '5 years'
    ) as has_recent_dup_link,
    -- outer apply-like: latest related activity timestamp combining votes and history for questions
    coalesce(
        case when fu.entity_type = 'question' then (
            select greatest(coalesce(qa.last_vote_at, 'epoch'::timestamp), coalesce(ph.closed_at, 'epoch'::timestamp), coalesce(ph.reopened_at, 'epoch'::timestamp))
            from q_activity qa
            left join post_history_flags ph on ph.postid = qa.qid
            where qa.qid = fu.entity_id::int
        ) end,
        fu.event_ts
    ) as latest_activity_ts,
    -- string manipulations and null logic
    case
        when fu.entity_type = 'user' then upper(coalesce(nullif(fu.category,''),'UNKNOWN'))
        when fu.entity_type = 'tag' then regexp_replace(coalesce(fu.tag,''), '[^a-z0-9_]+', '_', 'gi')
        else null
    end as normalized_category_or_tag
from final_union fu
where
    -- complicated predicate mixing types and metrics with null logic
    (
        (fu.entity_type = 'question' and (fu.metric_a + fu.metric_b + fu.metric_c) > 5)
        or
        (fu.entity_type = 'user' and coalesce(fu.metric_d,0) >= 100)
        or
        (fu.entity_type = 'cohort' and fu.rank_primary <= 12)
        or
        (fu.entity_type = 'tag' and coalesce(fu.metric_b,0) > 0)
    )
    and not (
        fu.entity_type = 'question'
        and exists (
            select 1 from post_history_flags phx
            where phx.postid = fu.entity_id::int
              and phx.mod_actions_present is true
              and coalesce(phx.closed_at, phx.reopened_at) is null
        )
    )
order by
    case fu.entity_type
        when 'question' then 1
        when 'user' then 2
        when 'tag' then 3
        when 'cohort' then 4
        else 5
    end,
    fu.rank_primary nulls last,
    fu.rank_secondary nulls last,
    fu.viewcount desc nulls last
limit 500;