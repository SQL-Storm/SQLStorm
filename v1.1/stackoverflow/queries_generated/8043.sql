-- {"query": "8043.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2964} 
with recent_posts as (
    select
        p.id,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.owneruserid,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.parentid,
        coalesce(p.answercount, 0) as answercount,
        coalesce(p.commentcount, 0) as commentcount
    from posts p
    where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
user_activity as (
    select
        u.id as userid,
        u.displayname,
        u.reputation,
        u.creationdate as user_creationdate,
        u.location,
        u.upvotes,
        u.downvotes,
        u.views,
        count(distinct b.id) filter (where b.class = 1) as gold_badges,
        count(distinct b.id) filter (where b.class = 2) as silver_badges,
        count(distinct b.id) filter (where b.class = 3) as bronze_badges,
        count(distinct p.id) as total_posts,
        count(distinct case when rp.posttypeid = 1 then rp.id end) as recent_questions,
        count(distinct case when rp.posttypeid = 2 then rp.id end) as recent_answers,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvote_actions,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvote_actions,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorite_actions
    from users u
    left join badges b on b.userid = u.id
    left join posts p on p.owneruserid = u.id
    left join recent_posts rp on rp.owneruserid = u.id
    left join votes v on v.userid = u.id and v.creationdate >= (select max(creationdate) - interval '365 days' from votes)
    group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.upvotes, u.downvotes, u.views
),
post_engagement as (
    select
        rp.id as post_id,
        rp.posttypeid,
        rp.owneruserid,
        rp.creationdate,
        rp.score,
        rp.viewcount,
        rp.answercount,
        rp.commentcount,
        -- engagement mix: normalize by log scale to avoid extreme skew
        (coalesce(rp.score,0) * 1.0)
        + ln(least(greatest(coalesce(rp.viewcount,0),1), 1000000))::numeric
        + (coalesce(rp.answercount,0) * 2.0)
        + (coalesce(rp.commentcount,0) * 0.5) as engagement_score,
        -- voting breakdown
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_recv,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_recv,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
    from recent_posts rp
    left join votes v on v.postid = rp.id
    group by rp.id, rp.posttypeid, rp.owneruserid, rp.creationdate, rp.score, rp.viewcount, rp.answercount, rp.commentcount
),
question_tags as (
    select
        p.id as question_id,
        p.title,
        p.tags,
        unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag
    from recent_posts p
    where p.posttypeid = 1
),
tag_stats as (
    select
        qt.tag,
        count(distinct qt.question_id) as questions_with_tag,
        sum(pe.upvotes_recv) as tag_upvotes_recv,
        sum(pe.downvotes_recv) as tag_downvotes_recv,
        avg(pe.engagement_score) as avg_engagement_score
    from question_tags qt
    join post_engagement pe on pe.post_id = qt.question_id
    group by qt.tag
),
duplicate_clusters as (
    select
        pl.relatedpostid as canonical_id,
        count(*) as dup_count,
        min(pl.creationdate) as first_link_date,
        max(pl.creationdate) as last_link_date
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.relatedpostid
),
edits_summary as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
        max(ph.creationdate) as last_edit_date,
        min(ph.creationdate) as first_edit_date,
        count(*) filter (where ph.posthistorytypeid = 10) as closed_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopened_events
    from posthistory ph
    where ph.creationdate >= (select max(creationdate) - interval '365 days' from posthistory)
    group by ph.postid
),
answers_to_recent_questions as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.creationdate as answer_date,
        a.score as answer_score,
        row_number() over (partition by a.parentid order by a.score desc nulls last, a.creationdate asc) as rn_by_score,
        dense_rank() over (partition by a.parentid order by a.creationdate) as dr_by_time
    from posts a
    where a.posttypeid = 2
      and exists (
          select 1 from recent_posts rq
          where rq.id = a.parentid and rq.posttypeid = 1
      )
),
accepted_answer_lag as (
    select
        q.id as question_id,
        q.creationdate as question_date,
        aa.id as accepted_answer_id,
        aa.creationdate as accepted_date,
        extract(epoch from (aa.creationdate - q.creationdate))/3600.0 as hours_to_accept,
        case when aa.id is null then 1 else 0 end as no_accepted_answer
    from recent_posts q
    left join posts aa on aa.id = q.acceptedanswerid
    where q.posttypeid = 1
),
owner_quality as (
    select
        pe.owneruserid as userid,
        count(*) as recent_posts_count,
        avg(pe.engagement_score) as avg_engagement,
        percentile_cont(0.9) within group (order by pe.engagement_score) as p90_engagement,
        sum(case when pe.posttypeid = 1 then 1 else 0 end) as recent_questions_count,
        sum(case when pe.posttypeid = 2 then 1 else 0 end) as recent_answers_count
    from post_engagement pe
    group by pe.owneruserid
),
ranked_posts as (
    select
        pe.*,
        ntile(20) over (order by pe.engagement_score desc nulls last) as engagement_ventile,
        row_number() over (partition by pe.owneruserid order by pe.engagement_score desc nulls last) as rn_owner_top
    from post_engagement pe
),
string_features as (
    select
        p.id as post_id,
        length(coalesce(p.title,'')) as title_len,
        length(regexp_replace(coalesce(p.body,''), '<[^>]*>', '', 'g')) as plain_body_len,
        (length(coalesce(p.tags,'')) - length(replace(coalesce(p.tags,''), '><', ''))) / 2 + case when p.tags is null then 0 else 1 end as tag_count_est,
        position('why' in lower(coalesce(p.title,''))) > 0 as title_contains_why,
        position('how' in lower(coalesce(p.title,''))) > 0 as title_contains_how
    from posts p
    where p.id in (select id from recent_posts)
),
questions_union as (
    select
        q.id as post_id,
        q.owneruserid as userid,
        'question' as post_kind
    from recent_posts q
    where q.posttypeid = 1
    union all
    select
        a.id as post_id,
        a.owneruserid as userid,
        'answer' as post_kind
    from recent_posts a
    where a.posttypeid = 2
),
activity_rollup as (
    select
        qa.userid,
        count(*) as total_recent_posts,
        count(*) filter (where qa.post_kind = 'question') as recent_questions,
        count(*) filter (where qa.post_kind = 'answer') as recent_answers
    from questions_union qa
    group by qa.userid
),
null_logic_demo as (
    select
        pe.post_id,
        coalesce(es.edit_count, 0) as edit_count,
        case when es.last_edit_date is null then pe.creationdate else es.last_edit_date end as last_touch_date,
        nullif(pe.upvotes_recv, 0) as upvotes_nonzero_or_null,
        coalesce(pe.downvotes_recv, 0) as downvotes_nonnull
    from post_engagement pe
    left join edits_summary es on es.postid = pe.post_id
),
owner_location_norm as (
    select
        u.id as userid,
        nullif(trim(lower(coalesce(u.location,''))), '') as norm_location
    from users u
),
final as (
    select
        rp.post_id,
        rp.posttypeid,
        rp.owneruserid,
        u.displayname,
        ol.norm_location,
        u.reputation,
        u.views as user_profile_views,
        ua.gold_badges,
        ua.silver_badges,
        ua.bronze_badges,
        ua.upvote_actions,
        ua.downvote_actions,
        ua.favorite_actions,
        oq.recent_posts_count as owner_recent_posts,
        oq.avg_engagement as owner_avg_engagement,
        oq.p90_engagement as owner_p90_engagement,
        rp.creationdate,
        rp.score,
        rp.viewcount,
        rp.answercount,
        rp.commentcount,
        rp.engagement_score,
        rp.upvotes_recv,
        rp.downvotes_recv,
        rp.bounty_started,
        rp.bounty_awarded,
        rp.engagement_ventile,
        s.title_len,
        s.plain_body_len,
        s.tag_count_est,
        s.title_contains_why,
        s.title_contains_how,
        coalesce(tps.avg_engagement_score, 0) as tag_avg_engagement_score_hint,
        coalesce(dc.dup_count, 0) as duplicate_cluster_size,
        es.edit_count,
        es.last_edit_date,
        es.closed_events,
        es.reopened_events,
        aqs.rn_by_score as best_answer_rank_by_score,
        aqs.dr_by_time as answer_time_rank,
        aal.hours_to_accept,
        aal.no_accepted_answer,
        nld.last_touch_date,
        nld.upvotes_nonzero_or_null,
        nld.downvotes_nonnull,
        row_number() over (order by rp.engagement_score desc nulls last, rp.viewcount desc nulls last) as global_rank
    from ranked_posts rp
    left join users u on u.id = rp.owneruserid
    left join owner_location_norm ol on ol.userid = rp.owneruserid
    left join user_activity ua on ua.userid = rp.owneruserid
    left join owner_quality oq on oq.userid = rp.owneruserid
    left join string_features s on s.post_id = rp.post_id
    left join (
        select qt.question_id, avg(ts.avg_engagement_score) as avg_engagement_score
        from question_tags qt
        join tag_stats ts on ts.tag = qt.tag
        group by qt.question_id
    ) tps on tps.question_id = rp.post_id
    left join duplicate_clusters dc on dc.canonical_id = rp.post_id
    left join edits_summary es on es.postid = rp.post_id
    left join answers_to_recent_questions aqs on aqs.answer_id = rp.post_id
    left join accepted_answer_lag aal on aal.question_id = rp.post_id
    left join null_logic_demo nld on nld.post_id = rp.post_id
)
select
    f.*,
    case
        when f.posttypeid = 1 and coalesce(f.answercount,0) = 0 then 'Q:no-answers'
        when f.posttypeid = 1 and f.no_accepted_answer = 1 then 'Q:unaccepted'
        when f.posttypeid = 2 and coalesce(f.best_answer_rank_by_score, 9999) = 1 then 'A:top'
        when f.posttypeid = 2 then 'A:other'
        else 'Other'
    end as post_bucket,
    case
        when f.engagement_ventile <= 4 then 'Top20%'
        when f.engagement_ventile <= 10 then 'Top50%'
        when f.engagement_ventile <= 16 then 'Bottom50%'
        else 'Bottom20%'
    end as engagement_band
from final f
where
    (
        f.posttypeid = 1
        and (
            f.tag_avg_engagement_score_hint > 0
            or f.duplicate_cluster_size > 0
            or f.hours_to_accept is null
        )
    )
    or (
        f.posttypeid = 2
        and (
            coalesce(f.best_answer_rank_by_score, 9999) <= 3
            or f.bounty_awarded > 0
        )
    )
order by
    f.engagement_ventile asc,
    f.global_rank asc
limit 500;