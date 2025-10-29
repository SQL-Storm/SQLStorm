-- {"query": "17.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3082} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (partition by date_trunc('month', u.creationdate) order by u.reputation desc, u.id) as rep_rank_in_cohort
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
question_posts as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.favoritecount,
        p.commentcount,
        p.closeddate,
        p.title,
        p.tags,
        p.acceptedanswerid,
        coalesce(p.viewcount, 0) / nullif(extract(epoch from (now() - p.creationdate)) / 86400.0, 0) as views_per_day,
        case when p.closeddate is not null then 1 else 0 end as is_closed
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as user_id,
        a.score as answer_score,
        a.creationdate as answer_date
    from posts a
    where a.posttypeid = 2
),
first_answer as (
    select
        q.post_id,
        min(a.answer_date) as first_answer_date,
        count(*) as total_answers_year
    from question_posts q
    left join answers a
      on a.question_id = q.post_id
     and a.answer_date >= q.creationdate
     and a.answer_date < q.creationdate + interval '365 days'
    group by q.post_id
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        count(*) as total_votes
    from votes v
    where v.creationdate >= (select max(creationdate) - interval '365 days' from votes)
    group by v.postid
),
postlinks_agg as (
    select
        pl.relatedpostid as canonical_id,
        sum(case when pl.linktypeid = 3 then 1 else 0 end) as dup_inbound_count,
        sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_inbound_count
    from postlinks pl
    where pl.creationdate >= (select max(creationdate) - interval '365 days' from postlinks)
    group by pl.relatedpostid
),
tag_expanded as (
    select
        q.post_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
    from question_posts q
    where q.tags is not null and q.tags like '<%>'
),
top_tags as (
    select
        tag,
        count(*) as tag_q_count,
        dense_rank() over (order by count(*) desc) as tag_rank
    from tag_expanded
    group by tag
),
user_activity as (
    select
        u.id as user_id,
        coalesce(sum(case when p.posttypeid = 1 then 1 else 0 end), 0) as questions_year,
        coalesce(sum(case when p.posttypeid = 2 then 1 else 0 end), 0) as answers_year,
        coalesce(sum(cast(coalesce(p.score,0) as bigint)), 0) as total_post_score_year,
        coalesce(sum(case when p.posttypeid = 1 then coalesce(p.viewcount,0) else 0 end), 0) as question_views_year
    from users u
    left join posts p
      on p.owneruserid = u.id
     and p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
    group by u.id
),
edits_cte as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
        min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,24)) as first_edit_date,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,24)) as last_edit_date
    from posthistory ph
    where ph.creationdate >= (select max(creationdate) - interval '365 days' from posthistory)
    group by ph.postid
),
comments_agg as (
    select
        c.postid,
        count(*) as comments_count,
        max(c.score) as max_comment_score,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.creationdate >= (select max(creationdate) - interval '365 days' from comments)
    group by c.postid
),
accepted_delta as (
    select
        q.post_id,
        case
            when q.acceptedanswerid is null then null
            else (select a2.creationdate from posts a2 where a2.id = q.acceptedanswerid and a2.posttypeid = 2)
        end as accepted_date,
        q.creationdate as question_date
    from question_posts q
),
question_quality as (
    select
        q.post_id,
        q.user_id,
        q.creationdate,
        q.score,
        q.viewcount,
        q.answercount,
        q.favoritecount,
        q.commentcount,
        q.title,
        q.tags,
        q.is_closed,
        fa.first_answer_date,
        extract(epoch from (fa.first_answer_date - q.creationdate))/3600.0 as hours_to_first_answer,
        ad.accepted_date,
        extract(epoch from (ad.accepted_date - q.creationdate))/3600.0 as hours_to_accept,
        va.upvotes,
        va.downvotes,
        va.bounty_started,
        va.bounty_awarded,
        va.total_votes,
        pa.dup_inbound_count,
        pa.linked_inbound_count,
        ed.edit_events,
        ed.first_edit_date,
        ed.last_edit_date,
        ca.comments_count,
        ca.max_comment_score,
        ca.last_comment_date,
        coalesce(va.upvotes,0) - coalesce(va.downvotes,0) as net_votes,
        case when q.score is null then null when q.viewcount is null or q.viewcount = 0 then null else (q.score::numeric / nullif(q.viewcount,0)) end as score_per_view,
        case when q.answercount is null or q.answercount = 0 then 0 else coalesce(va.upvotes,0)::numeric / q.answercount end as upvotes_per_answer
    from question_posts q
    left join first_answer fa on fa.post_id = q.post_id
    left join votes_agg va on va.postid = q.post_id
    left join postlinks_agg pa on pa.canonical_id = q.post_id
    left join edits_cte ed on ed.postid = q.post_id
    left join comments_agg ca on ca.postid = q.post_id
    left join accepted_delta ad on ad.post_id = q.post_id
),
user_enriched as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        ru.rep_rank_in_cohort,
        ua.questions_year,
        ua.answers_year,
        ua.total_post_score_year,
        ua.question_views_year,
        coalesce(ua.total_post_score_year,0) - coalesce(ua.question_views_year,0)/1000.0 as score_minus_views_scaled
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
),
badge_agg as (
    select
        b.userid,
        sum(case when b.class = 1 then 1 else 0 end) as gold_count,
        sum(case when b.class = 2 then 1 else 0 end) as silver_count,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
        sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
    from badges b
    where b.date >= (select max(date) - interval '365 days' from badges)
    group by b.userid
),
question_scored as (
    select
        qq.*,
        ue.displayname,
        ue.reputation,
        ue.cohort_month,
        ue.rep_rank_in_cohort,
        coalesce(ba.gold_count,0) as gold_badges_year,
        coalesce(ba.silver_count,0) as silver_badges_year,
        coalesce(ba.bronze_count,0) as bronze_badges_year,
        coalesce(ba.tag_badges,0) as tag_badges_year,
        /* composite score with NULL-safe components and scaling */
        (
          coalesce(qq.score,0) * 2
          + coalesce(qq.net_votes,0)
          + coalesce(qq.viewcount,0) / 50.0
          + case when qq.hours_to_first_answer is null then -5 else greatest(0, 24 - least(168, qq.hours_to_first_answer)) end
          + case when qq.hours_to_accept is null then 0 else greatest(0, 48 - least(336, qq.hours_to_accept)) end
          + coalesce(qq.favoritecount,0) * 3
          + coalesce(qq.commentcount,0) * 0.5
          + coalesce(qq.dup_inbound_count,0) * -10
          + coalesce(qq.linked_inbound_count,0) * 2
          + coalesce(qq.edit_events,0) * 1.5
          + case when qq.is_closed = 1 then -25 else 0 end
          + coalesce(ue.reputation,0) / 100.0
          + coalesce(ba.gold_count,0) * 5
          + coalesce(ba.silver_count,0) * 2
          + coalesce(ba.bronze_count,0) * 1
        ) as composite_quality_score
    from question_quality qq
    left join user_enriched ue on ue.user_id = qq.user_id
    left join badge_agg ba on ba.userid = qq.user_id
),
ranked as (
    select
        qs.*,
        row_number() over (order by composite_quality_score desc, qs.viewcount desc, qs.score desc, qs.post_id) as global_rank,
        dense_rank() over (partition by date_trunc('month', qs.creationdate) order by composite_quality_score desc) as month_rank,
        percentile_cont(0.9) within group (order by composite_quality_score) over () as p90_score
    from question_scored qs
),
filtered as (
    select
        r.*
    from ranked r
    where
        (
          exists (
            select 1
            from tag_expanded te
            join top_tags tt on tt.tag = te.tag and tt.tag_rank <= 10
            where te.post_id = r.post_id
          )
          or r.composite_quality_score >= r.p90_score
        )
        and coalesce(r.viewcount,0) > 0
)
select
    f.post_id,
    coalesce(f.title, '(no title)') as title,
    f.displayname as owner_displayname,
    f.reputation,
    f.cohort_month,
    f.rep_rank_in_cohort,
    f.creationdate as question_date,
    f.viewcount,
    f.score,
    f.net_votes,
    f.answercount,
    f.favoritecount,
    f.commentcount,
    f.is_closed,
    f.first_answer_date,
    f.hours_to_first_answer,
    f.accepted_date,
    f.hours_to_accept,
    f.upvotes,
    f.downvotes,
    f.bounty_started,
    f.bounty_awarded,
    f.dup_inbound_count,
    f.linked_inbound_count,
    f.edit_events,
    f.first_edit_date,
    f.last_edit_date,
    f.comments_count,
    f.max_comment_score,
    f.last_comment_date,
    f.score_per_view,
    f.upvotes_per_answer,
    f.gold_badges_year,
    f.silver_badges_year,
    f.bronze_badges_year,
    f.tag_badges_year,
    f.composite_quality_score,
    f.global_rank,
    f.month_rank,
    string_agg(distinct te.tag, ', ' order by te.tag) as top_tags_present
from filtered f
left join tag_expanded te on te.post_id = f.post_id
group by
    f.post_id, f.title, f.displayname, f.reputation, f.cohort_month, f.rep_rank_in_cohort,
    f.creationdate, f.viewcount, f.score, f.net_votes, f.answercount, f.favoritecount,
    f.commentcount, f.is_closed, f.first_answer_date, f.hours_to_first_answer, f.accepted_date,
    f.hours_to_accept, f.upvotes, f.downvotes, f.bounty_started, f.bounty_awarded,
    f.dup_inbound_count, f.linked_inbound_count, f.edit_events, f.first_edit_date, f.last_edit_date,
    f.comments_count, f.max_comment_score, f.last_comment_date, f.score_per_view, f.upvotes_per_answer,
    f.gold_badges_year, f.silver_badges_year, f.bronze_badges_year, f.tag_badges_year,
    f.composite_quality_score, f.global_rank, f.month_rank
order by f.global_rank
limit 200;