-- {"query": "781.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3136} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
        dense_rank() over (order by u.creationdate desc, u.id desc) as recency_rank
    from users u
),
question_activity as (
    select
        p.id as question_id,
        p.owneruserid as owner_user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.favoritecount,
        p.commentcount,
        p.tags,
        p.title,
        p.closeddate,
        p.acceptedanswerid,
        (case when p.closeddate is not null then 1 else 0 end) as is_closed,
        coalesce(p.viewcount,0) + 10 * coalesce(p.answercount,0) + 5 * coalesce(p.favoritecount,0) + 2 * coalesce(p.commentcount,0) + 25 * (case when p.acceptedanswerid is not null then 1 else 0 end) as engagement_score
    from posts p
    where p.posttypeid = 1
),
answers_by_question as (
    select
        a.parentid as question_id,
        count(*) as answer_cnt,
        sum(a.score) as answer_score_sum,
        avg(a.score) filter (where a.score is not null) as avg_answer_score,
        max(a.creationdate) as last_answer_date
    from posts a
    where a.posttypeid = 2
    group by a.parentid
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        min(v.creationdate) as first_vote_at,
        max(v.creationdate) as last_vote_at
    from votes v
    group by v.postid
),
close_reasons as (
    select
        ph.postid as question_id,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as closed_at,
        max(crt.name) filter (
            where ph.posthistorytypeid = 10
              and ph.comment ~ '^[0-9]+$'
        ) as close_reason_name_guess, -- only populated if PostHistory.comment matched numeric close reason
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events
    from posthistory ph
    left join closerreasontypes crt
      on crt.id::text = ph.comment
    group by ph.postid
),
linked_dupes as (
    select
        pl.postid as question_id,
        count(*) filter (where pl.linktypeid = 1) as linked_count,
        count(*) filter (where pl.linktypeid = 3) as duplicate_count,
        count(distinct case when pl.linktypeid in (1,3) then pl.relatedpostid end) as distinct_related
    from postlinks pl
    group by pl.postid
),
tag_exploded as (
    select
        q.question_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
    from question_activity q
    where q.tags is not null and q.tags like '<%>'
),
tag_stats as (
    select
        te.question_id,
        array_agg(te.tag order by te.tag) as tags_array,
        count(*) as tag_count,
        min(te.tag) as alpha_first_tag,
        max(te.tag) as alpha_last_tag
    from tag_exploded te
    group by te.question_id
),
badge_agg as (
    select
        b.userid as user_id,
        count(*) as total_badges,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where b.tagbased = 1) as tag_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
comment_agg as (
    select
        c.postid,
        count(*) as comment_cnt,
        sum(c.score) as comment_score_sum,
        avg(c.score) filter (where c.score is not null) as avg_comment_score,
        max(length(c.text)) as max_comment_len,
        min(c.creationdate) as first_comment_at,
        max(c.creationdate) as last_comment_at,
        count(*) filter (where c.userid is null) as anon_comment_cnt
    from comments c
    group by c.postid
),
user_post_span as (
    select
        u.id as user_id,
        min(p.creationdate) as first_post_at,
        max(p.creationdate) as last_post_at,
        extract(epoch from (max(p.creationdate) - min(p.creationdate))) as posting_span_seconds,
        count(*) as total_posts
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
accepted_latency as (
    select
        q.id as question_id,
        q.creationdate as question_created_at,
        a.creationdate as accepted_created_at,
        extract(epoch from (a.creationdate - q.creationdate)) as accept_latency_seconds
    from posts q
    join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1 and q.acceptedanswerid is not null
),
ranked_questions as (
    select
        qa.question_id,
        qa.owner_user_id,
        qa.creationdate,
        qa.score,
        qa.viewcount,
        qa.answercount,
        qa.favoritecount,
        qa.commentcount,
        qa.title,
        qa.engagement_score,
        row_number() over (order by qa.engagement_score desc, qa.viewcount desc, qa.score desc, qa.question_id desc) as engagement_rank,
        percentile_cont(0.9) within group (order by qa.engagement_score) over () as p90_engagement
    from question_activity qa
),
owner_enrichment as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate as user_created_at,
        ru.location,
        ru.websiteurl,
        ru.recency_rank,
        ba.total_badges,
        ba.gold_badges,
        ba.silver_badges,
        ba.bronze_badges,
        ba.tag_badges,
        ups.first_post_at,
        ups.last_post_at,
        ups.posting_span_seconds,
        ups.total_posts
    from recent_users ru
    left join badge_agg ba on ba.user_id = ru.user_id
    left join user_post_span ups on ups.user_id = ru.user_id
),
question_scored as (
    select
        rq.*,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(va.favorites,0) as favorites_votes,
        coalesce(va.bounty_started,0) as bounty_started,
        coalesce(va.bounty_awarded,0) as bounty_awarded,
        coalesce(la.linked_count,0) as linked_count,
        coalesce(la.duplicate_count,0) as duplicate_count,
        coalesce(la.distinct_related,0) as distinct_related,
        coalesce(aa.answer_cnt,0) as answer_cnt,
        coalesce(aa.answer_score_sum,0) as answer_score_sum,
        aa.avg_answer_score,
        aa.last_answer_date,
        coalesce(ca.comment_cnt,0) as comment_cnt_calc,
        coalesce(ca.comment_score_sum,0) as comment_score_sum,
        ca.avg_comment_score,
        ca.max_comment_len,
        ca.first_comment_at,
        ca.last_comment_at,
        cr.closed_at,
        cr.close_reason_name_guess,
        cr.reopen_events,
        ts.tags_array,
        ts.tag_count,
        ts.alpha_first_tag,
        ts.alpha_last_tag,
        al.accept_latency_seconds,
        -- composite score mixing multiple dimensions with null handling and scaling
        (
            0.40 * ln(1 + greatest(0, rq.viewcount))
          + 0.25 * greatest(0, rq.score)
          + 0.20 * ln(1 + coalesce(va.upvotes,0) - coalesce(va.downvotes,0) + coalesce(va.favorites,0))
          + 0.10 * ln(1 + coalesce(aa.answer_cnt,0))
          + 0.05 * ln(1 + coalesce(ca.comment_cnt,0))
          - 0.15 * case when cr.closed_at is not null then 1 else 0 end
          + 0.10 * case when al.accept_latency_seconds is not null then 1.0 / nullif((al.accept_latency_seconds/3600.0)+1,0) else 0 end
        ) as composite_score
    from ranked_questions rq
    left join votes_agg va on va.postid = rq.question_id
    left join linked_dupes la on la.question_id = rq.question_id
    left join answers_by_question aa on aa.question_id = rq.question_id
    left join comment_agg ca on ca.postid = rq.question_id
    left join close_reasons cr on cr.question_id = rq.question_id
    left join tag_stats ts on ts.question_id = rq.question_id
    left join accepted_latency al on al.question_id = rq.question_id
),
user_rollup as (
    select
        qs.owner_user_id as user_id,
        count(*) as questions_count,
        sum(case when qs.closed_at is not null then 1 else 0 end) as questions_closed,
        avg(qs.composite_score) as avg_composite_score,
        max(qs.composite_score) as max_composite_score,
        percentile_cont(0.5) within group (order by qs.composite_score) as p50_composite_score,
        sum(qs.viewcount) as total_views,
        sum(qs.upvotes) as total_upvotes,
        sum(qs.downvotes) as total_downvotes,
        sum(qs.answer_cnt) as total_answers_received,
        count(*) filter (where qs.accept_latency_seconds is not null) as with_accepted,
        avg(qs.accept_latency_seconds) filter (where qs.accept_latency_seconds is not null) as avg_accept_latency_sec
    from question_scored qs
    group by qs.owner_user_id
),
final as (
    select
        qs.question_id,
        qs.title,
        qs.creationdate as question_created_at,
        oe.user_id,
        oe.displayname as owner_displayname,
        oe.reputation,
        oe.location,
        oe.websiteurl,
        oe.total_posts,
        oe.total_badges,
        oe.gold_badges,
        oe.silver_badges,
        oe.bronze_badges,
        ur.questions_count,
        ur.questions_closed,
        ur.avg_composite_score,
        ur.max_composite_score,
        ur.total_views,
        ur.total_upvotes,
        ur.total_downvotes,
        qs.viewcount,
        qs.score as question_score,
        qs.answercount,
        qs.favoritecount,
        qs.commentcount,
        qs.upvotes,
        qs.downvotes,
        qs.favorites_votes,
        qs.bounty_started,
        qs.bounty_awarded,
        qs.linked_count,
        qs.duplicate_count,
        qs.distinct_related,
        qs.answer_cnt,
        qs.answer_score_sum,
        qs.avg_answer_score,
        qs.last_answer_date,
        qs.comment_cnt_calc,
        qs.comment_score_sum,
        qs.avg_comment_score,
        qs.max_comment_len,
        qs.first_comment_at,
        qs.last_comment_at,
        qs.closed_at,
        qs.close_reason_name_guess,
        qs.tags_array,
        qs.tag_count,
        qs.alpha_first_tag,
        qs.alpha_last_tag,
        qs.accept_latency_seconds,
        qs.engagement_score,
        qs.engagement_rank,
        qs.p90_engagement,
        qs.composite_score,
        case
            when qs.engagement_score >= qs.p90_engagement then 'P90+'
            when qs.engagement_rank <= 100 then 'Top100ByRank'
            when qs.closed_at is not null then 'Closed'
            when qs.duplicate_count > 0 then 'HasDuplicate'
            else 'Normal'
        end as bucket,
        -- correlated subquery to compute distinct commenters excluding owner
        (
            select count(distinct c.userid)
            from comments c
            where c.postid = qs.question_id
              and (c.userid is distinct from qs.owner_user_id)
        ) as distinct_commenters_ex_owner,
        -- string expressions
        substring(coalesce(qs.title,''), 1, 120) || case when length(coalesce(qs.title,'')) > 120 then '…' else '' end as title_preview,
        coalesce(array_to_string(qs.tags_array, ','), '(no-tags)') as tags_csv
    from question_scored qs
    left join owner_enrichment oe on oe.user_id = qs.owner_user_id
    left join user_rollup ur on ur.user_id = qs.owner_user_id
    where qs.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
      and (
            qs.composite_score > (
                select avg(composite_score) + stddev_pop(composite_score)
                from question_scored
            )
            or qs.bucket in ('Closed','HasDuplicate')
          )
)
select *
from final
where (
        -- complicated predicates combining null and numeric logic
        (close_reason_name_guess is null and duplicate_count = 0)
        or (close_reason_name_guess is not null and composite_score >= 0)
      )
  and case when tag_count is null then 0 else tag_count end between 0 and 5
  and (reputation >= 100 or (reputation is null and total_posts is null))
order by composite_score desc nulls last, engagement_rank asc, question_id desc
limit 250;