-- {"query": "834.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2654}
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(cast(u.websiteurl as varchar)), ''), 'unknown') as websiteurl_norm
    from users u
    where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from users)
),
tag_exploded as (
    select p.id as post_id,
           lower(trim(cast(tg as varchar))) as tag_name
    from posts p,
         lateral unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tg
    where p.posttypeid = 1
      and p.tags is not null
),
hot_questions as (
    select ph.postid,
           min(ph.creationdate) as first_hot_date,
           count(*) filter (where ph.posthistorytypeid = 52) as hot_count_add,
           count(*) filter (where ph.posthistorytypeid = 53) as hot_count_remove
    from posthistory ph
    where ph.posthistorytypeid in (52,53)
    group by ph.postid
),
dup_links as (
    select pl.postid,
           count(*) filter (where pl.linktypeid = 3) as duplicate_links,
           count(*) filter (where pl.linktypeid = 1) as linked_links,
           max(pl.creationdate) as last_link_date
    from postlinks pl
    group by pl.postid
),
vote_agg as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
           max(v.creationdate) as last_vote_at
    from votes v
    group by v.postid
),
answers as (
    select a.parentid as question_id,
           count(*) as answer_count,
           max(a.score) as max_answer_score,
           avg(cast(a.score as numeric)) as avg_answer_score,
           min(a.creationdate) as first_answer_at,
           max(a.creationdate) as last_answer_at
    from posts a
    where a.posttypeid = 2
    group by a.parentid
),
comment_agg as (
    select c.postid,
           count(*) as comment_count,
           sum(c.score) as comment_score_sum,
           max(c.creationdate) as last_comment_at
    from comments c
    group by c.postid
),
user_badges as (
    select b.userid,
           count(*) as total_badges,
           count(*) filter (where b.class = 1) as gold_badges,
           count(*) filter (where b.class = 2) as silver_badges,
           count(*) filter (where b.class = 3) as bronze_badges,
           max(b.date) as last_badge_at
    from badges b
    group by b.userid
),
question_core as (
    select q.id as question_id,
           q.creationdate,
           q.owneruserid,
           q.score as question_score,
           q.viewcount,
           q.favoritecount,
           q.title,
           q.tags,
           q.acceptedanswerid,
           q.closeddate,
           q.lastactivitydate,
           q.commentcount as question_comment_count
    from posts q
    where q.posttypeid = 1
),
normalized_tags as (
    select qc.question_id,
           array_agg(distinct te.tag_name order by te.tag_name) as tags_array,
           count(distinct te.tag_name) as tag_count
    from question_core qc
    left join tag_exploded te on te.post_id = qc.question_id
    group by qc.question_id
),
tag_stats as (
    select te.tag_name,
           count(distinct te.post_id) as questions_with_tag,
           sum(p.score) filter (where p.posttypeid = 1) as sum_question_scores,
           avg(nullif(p.viewcount,0)) filter (where p.posttypeid = 1) as avg_views_nonzero
    from tag_exploded te
    join posts p on p.id = te.post_id
    group by te.tag_name
),
user_activity as (
    select u.id as user_id,
           count(*) filter (where p.posttypeid = 1) as questions_posted,
           count(*) filter (where p.posttypeid = 2) as answers_posted,
           max(p.lastactivitydate) as last_post_activity
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
recent_hot_dups as (
    select qc.question_id
    from question_core qc
    left join hot_questions hq on hq.postid = qc.question_id
    left join dup_links dl on dl.postid = qc.question_id
    where qc.creationdate >= (select date_trunc('year', max(creationdate)) - interval '3 years' from posts)
      and coalesce(hq.hot_count_add,0) > 0
      and coalesce(dl.duplicate_links,0) >= 1
),
ranked_questions as (
    select
        qc.question_id,
        qc.owneruserid,
        qc.creationdate,
        qc.title,
        qc.tags,
        qc.acceptedanswerid,
        qc.closeddate,
        qc.lastactivitydate,
        coalesce(va.net_votes,0) as net_votes,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(va.favorites,0) as favorites,
        coalesce(an.answer_count,0) as answer_count,
        an.max_answer_score,
        an.avg_answer_score,
        coalesce(ca.comment_count,0) as comment_count,
        coalesce(ca.comment_score_sum,0) as comment_score_sum,
        nt.tags_array,
        nt.tag_count,
        hq.first_hot_date,
        hq.hot_count_add,
        hq.hot_count_remove,
        dl.duplicate_links,
        dl.linked_links,
        dl.last_link_date,
        case when qc.acceptedanswerid is not null then 1 else 0 end as has_accepted,
        case when qc.closeddate is not null then 1 else 0 end as is_closed,
        row_number() over (partition by qc.owneruserid order by coalesce(va.net_votes,0) desc, coalesce(an.answer_count,0) desc, qc.creationdate desc) as rn_by_user,
        rank() over (order by coalesce(va.net_votes,0) desc, coalesce(an.answer_count,0) desc, coalesce(hq.hot_count_add,0) desc, qc.viewcount desc nulls last) as global_rank,
        sum(coalesce(va.net_votes,0)) over (order by qc.creationdate rows between unbounded preceding and current row) as running_net_votes_time,
        avg(coalesce(va.net_votes,0)) over (partition by date_trunc('month', qc.creationdate) order by date_trunc('month', qc.creationdate)) as avg_net_votes_by_month
    from question_core qc
    left join vote_agg va on va.postid = qc.question_id
    left join answers an on an.question_id = qc.question_id
    left join comment_agg ca on ca.postid = qc.question_id
    left join normalized_tags nt on nt.question_id = qc.question_id
    left join hot_questions hq on hq.postid = qc.question_id
    left join dup_links dl on dl.postid = qc.question_id
    group by
        qc.question_id,
        qc.owneruserid,
        qc.creationdate,
        qc.title,
        qc.tags,
        qc.acceptedanswerid,
        qc.closeddate,
        qc.lastactivitydate,
        va.net_votes,
        va.upvotes,
        va.downvotes,
        va.favorites,
        an.answer_count,
        an.max_answer_score,
        an.avg_answer_score,
        ca.comment_count,
        ca.comment_score_sum,
        nt.tags_array,
        nt.tag_count,
        hq.first_hot_date,
        hq.hot_count_add,
        hq.hot_count_remove,
        dl.duplicate_links,
        dl.linked_links,
        dl.last_link_date,
        qc.acceptedanswerid,
        qc.closeddate,
        qc.viewcount
),
user_enriched as (
    select ru.user_id,
           ru.displayname,
           ru.reputation,
           ru.creationdate,
           ru.location,
           ru.websiteurl_norm,
           ua.questions_posted,
           ua.answers_posted,
           ub.total_badges,
           ub.gold_badges,
           ub.silver_badges,
           ub.bronze_badges,
           ub.last_badge_at,
           ua.last_post_activity
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_badges ub on ub.userid = ru.user_id
),
final_scored as (
    select
        rq.question_id,
        rq.owneruserid,
        rq.creationdate,
        rq.title,
        rq.tags,
        rq.acceptedanswerid,
        rq.closeddate,
        rq.lastactivitydate,
        rq.net_votes,
        rq.upvotes,
        rq.downvotes,
        rq.favorites,
        rq.answer_count,
        rq.max_answer_score,
        rq.avg_answer_score,
        rq.comment_count,
        rq.comment_score_sum,
        rq.tags_array,
        rq.tag_count,
        rq.first_hot_date,
        rq.hot_count_add,
        rq.hot_count_remove,
        rq.duplicate_links,
        rq.linked_links,
        rq.last_link_date,
        rq.has_accepted,
        rq.is_closed,
        rq.rn_by_user,
        rq.global_rank,
        rq.running_net_votes_time,
        rq.avg_net_votes_by_month,
        ue.displayname,
        ue.reputation,
        ue.location,
        ue.websiteurl_norm,
        ue.questions_posted,
        ue.answers_posted,
        ue.total_badges,
        ue.gold_badges,
        ue.silver_badges,
        ue.bronze_badges,
        (
            1.0 * coalesce(rq.net_votes,0)
          + 0.5 * coalesce(rq.upvotes,0)
          - 0.7 * coalesce(rq.downvotes,0)
          + 0.8 * coalesce(rq.answer_count,0)
          + 0.2 * coalesce(rq.comment_count,0)
          + case when rq.has_accepted = 1 then 3 else 0 end
          - case when rq.is_closed = 1 then 5 else 0 end
          - least(coalesce(rq.duplicate_links,0), 5) * 0.6
          + least(coalesce(ue.gold_badges,0), 10) * 0.3
          + least(coalesce(ue.silver_badges,0), 20) * 0.15
          + least(coalesce(ue.bronze_badges,0), 30) * 0.05
          + case when rq.first_hot_date is not null then 2 else 0 end
          + case when rq.tag_count >= 5 then -1.5 when rq.tag_count between 3 and 4 then 0.5 else 0 end
          + case when lower(coalesce(ue.location,'')) like '%remote%' then 0.2 else 0 end
          + greatest(0, 2 - extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - rq.creationdate))/86400.0)
        ) as composite_score
    from ranked_questions rq
    left join user_enriched ue on ue.user_id = rq.owneruserid
    where rq.creationdate >= (select date_trunc('month', max(creationdate)) - interval '36 months' from posts)
),
final_score_stats as (
    select composite_score from final_scored
)
select
    fs.question_id,
    coalesce(fs.displayname, '(unknown)') as author,
    fs.reputation,
    coalesce(nullif(fs.title,''), '[no title]') as title,
    fs.tags_array,
    fs.tag_count,
    fs.net_votes,
    fs.upvotes,
    fs.downvotes,
    fs.answer_count,
    fs.max_answer_score,
    fs.avg_answer_score,
    fs.comment_count,
    fs.comment_score_sum,
    fs.favorites,
    fs.has_accepted,
    fs.is_closed,
    fs.first_hot_date,
    fs.hot_count_add,
    fs.hot_count_remove,
    fs.duplicate_links,
    fs.linked_links,
    fs.creationdate,
    fs.lastactivitydate,
    fs.global_rank,
    fs.rn_by_user,
    fs.running_net_votes_time,
    fs.avg_net_votes_by_month,
    fs.composite_score,
    case
        when fs.is_closed = 1 and fs.duplicate_links > 0 then 'Closed as duplicate'
        when fs.is_closed = 1 then 'Closed'
        when fs.first_hot_date is not null then 'Hot'
        else 'Open'
    end as status_label
from final_scored fs
where (
        fs.composite_score > (
            select percentile_disc(0.85) within group (order by composite_score)
            from final_score_stats
        )
        or fs.global_rank <= 100
      )
  and not exists (
        select 1
        from posthistory ph
        where ph.postid = fs.question_id
          and ph.posthistorytypeid in (10,12,14,19,35)
          and ph.creationdate > fs.creationdate
      )
order by fs.composite_score desc, fs.global_rank asc, fs.creationdate desc
limit 500;