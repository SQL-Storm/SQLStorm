with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.location,
        u.creationdate,
        u.lastaccessdate,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from users)
),
question_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        sum(coalesce(p.viewcount, 0)) filter (where p.posttypeid = 1) as q_views,
        sum(coalesce(p.score, 0)) filter (where p.posttypeid = 1) as q_score,
        count(*) filter (where p.posttypeid = 1 and p.acceptedanswerid is not null) as q_with_accepted,
        avg(nullif(p.answercount, 0)) filter (where p.posttypeid = 1) as avg_answers_per_q
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= (select min(creationdate) from recent_users)
    group by p.owneruserid
),
answer_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score, 0)) filter (where p.posttypeid = 2) as a_score,
        avg(coalesce(p.score, 0)) filter (where p.posttypeid = 2) as avg_a_score,
        sum(case when p.score >= 5 then 1 else 0 end) filter (where p.posttypeid = 2) as a_highscore_cnt
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= (select min(creationdate) from recent_users)
    group by p.owneruserid
),
comment_activity as (
    select
        c.userid as user_id,
        count(*) as c_count,
        sum(coalesce(c.score,0)) as c_score,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
      and c.creationdate >= (select min(creationdate) from recent_users)
    group by c.userid
),
vote_breakdown as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid in (8,9)) as bounties_involved,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total
    from votes v
    where v.userid is not null
      and v.creationdate >= (select min(creationdate) from recent_users)
    group by v.userid
),
badges_rollup as (
    select
        b.userid as user_id,
        count(*) as badge_cnt,
        count(*) filter (where b.class = 1) as gold_cnt,
        count(*) filter (where b.class = 2) as silver_cnt,
        count(*) filter (where b.class = 3) as bronze_cnt,
        count(*) filter (where b.tagbased = true) as tag_badges_cnt,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    where b.date >= (select min(creationdate) from recent_users)
    group by b.userid
),
user_posted_tags as (
    select
        p.owneruserid as user_id,
        lower(trim(t.tag)) as tagname,
        count(*) as tag_posts
    from posts p
    cross join lateral (
        select unnest(
            case
                when p.posttypeid = 1 and p.tags is not null
                    then string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
                else array[]::text[] /* replaced below for dialects that don't support ::; keep for engines that do */
            end
        ) as tag
    ) t
    where p.owneruserid is not null
      and p.creationdate >= (select min(creationdate) from recent_users)
    group by p.owneruserid, lower(trim(t.tag))
),
top_tag_per_user as (
    select distinct on (user_id)
        user_id, tagname, tag_posts
    from (
        select
            upt.*,
            row_number() over (partition by user_id order by tag_posts desc, tagname) as rn
        from user_posted_tags upt
    ) s
    where rn = 1
    order by user_id, tag_posts desc, tagname
),
postlinks_stats as (
    select
        p.owneruserid as user_id,
        count(distinct pl.id) filter (where pl.linktypeid = 3) as dup_links,
        count(distinct pl.id) filter (where pl.linktypeid = 1) as related_links
    from posts p
    left join postlinks pl
      on pl.postid = p.id
    where p.owneruserid is not null
      and p.creationdate >= (select min(creationdate) from recent_users)
    group by p.owneruserid
),
closure_reasons as (
    select
        ph.postid,
        max(ph.creationdate) as last_close_date,
        max(cast(ph.comment as integer)) filter (where ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+$') as last_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
closed_questions_per_user as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1 and p.closeddate is not null) as closed_q_count,
        count(*) filter (where p.posttypeid = 1 and p.closeddate is null) as open_q_count,
        count(*) filter (where p.posttypeid = 1 and c.last_close_reason_id = 101) as dup_reason_count
    from posts p
    left join closure_reasons c
      on c.postid = p.id
    where p.owneruserid is not null
      and p.creationdate >= (select min(creationdate) from recent_users)
    group by p.owneruserid
),
activity_timeline as (
    select
        u.user_id,
        date_trunc('month', p.creationdate) as month_bucket,
        count(*) filter (where p.posttypeid = 1) as q_monthly,
        count(*) filter (where p.posttypeid = 2) as a_monthly,
        count(c.id) as comments_monthly
    from recent_users u
    left join posts p
      on p.owneruserid = u.user_id
     and p.creationdate >= u.creationdate
    left join comments c
      on c.userid = u.user_id
     and c.creationdate >= u.creationdate
     and date_trunc('month', c.creationdate) = date_trunc('month', coalesce(p.creationdate, c.creationdate))
    group by u.user_id, date_trunc('month', p.creationdate)
),
activity_sparseness as (
    select
        user_id,
        count(*) as active_months,
        sum(q_monthly + a_monthly + comments_monthly) as total_interactions,
        stddev_pop(q_monthly + a_monthly + comments_monthly) as activity_stddev
    from activity_timeline
    group by user_id
),
user_quality_score as (
    select
        u.user_id,
        round( greatest(0,
            0.4 * coalesce(qa.q_score,0) +
            0.5 * coalesce(aa.a_score,0) +
            0.1 * (coalesce(vb.upvotes_cast,0) - 1.5 * coalesce(vb.downvotes_cast,0)) +
            0.2 * coalesce(br.gold_cnt,0) +
            0.05 * coalesce(br.silver_cnt,0) +
            0.02 * coalesce(br.bronze_cnt,0) -
            0.3 * coalesce(cq.closed_q_count,0) +
            0.1 * coalesce(pl.related_links,0) -
            0.2 * coalesce(pl.dup_links,0)
        ), 2) as quality_score
    from recent_users u
    left join question_activity qa on qa.user_id = u.user_id
    left join answer_activity aa on aa.user_id = u.user_id
    left join vote_breakdown vb on vb.user_id = u.user_id
    left join badges_rollup br on br.user_id = u.user_id
    left join closed_questions_per_user cq on cq.user_id = u.user_id
    left join postlinks_stats pl on pl.user_id = u.user_id
),
normalized_metrics as (
    select
        u.user_id,
        u.displayname,
        u.reputation,
        u.cohort_month,
        coalesce(qa.q_count, 0) as q_count,
        coalesce(qa.q_views, 0) as q_views,
        coalesce(qa.q_with_accepted, 0) as q_with_accepted,
        coalesce(aa.a_count, 0) as a_count,
        coalesce(vb.upvotes_cast, 0) as upvotes_cast,
        coalesce(vb.downvotes_cast, 0) as downvotes_cast,
        coalesce(vb.bounty_total, 0) as bounty_total,
        coalesce(br.badge_cnt, 0) as badge_cnt,
        coalesce(br.gold_cnt, 0) as gold_cnt,
        coalesce(br.silver_cnt, 0) as silver_cnt,
        coalesce(br.bronze_cnt, 0) as bronze_cnt,
        coalesce(ca.c_count, 0) as c_count,
        coalesce(ps.related_links, 0) as related_links,
        coalesce(ps.dup_links, 0) as dup_links,
        coalesce(cq.closed_q_count, 0) as closed_q_count,
        coalesce(cq.open_q_count, 0) as open_q_count,
        coalesce(at.active_months, 0) as active_months,
        coalesce(at.total_interactions, 0) as total_interactions,
        coalesce(at.activity_stddev, 0) as activity_stddev,
        coalesce(tt.tagname, '(none)') as top_tag,
        coalesce(tt.tag_posts, 0) as top_tag_posts
    from recent_users u
    left join question_activity qa on qa.user_id = u.user_id
    left join answer_activity aa on aa.user_id = u.user_id
    left join vote_breakdown vb on vb.user_id = u.user_id
    left join badges_rollup br on br.user_id = u.user_id
    left join comment_activity ca on ca.user_id = u.user_id
    left join postlinks_stats ps on ps.user_id = u.user_id
    left join closed_questions_per_user cq on cq.user_id = u.user_id
    left join activity_sparseness at on at.user_id = u.user_id
    left join top_tag_per_user tt on tt.user_id = u.user_id
),
cohort_stats as (
    select
        cohort_month,
        count(*) as users_in_cohort,
        avg(reputation) as avg_rep,
        percentile_cont(0.5) within group (order by reputation) as p50_rep
    from recent_users
    group by cohort_month
),
ranked_users as (
    select
        nm.*,
        cs.users_in_cohort,
        cs.avg_rep,
        cs.p50_rep,
        uq.quality_score,
        rank() over (partition by nm.cohort_month order by uq.quality_score desc, nm.reputation desc, nm.user_id) as cohort_rank,
        dense_rank() over (order by uq.quality_score desc) as global_dense_rank,
        row_number() over (order by uq.quality_score desc, nm.user_id) as global_rownum
    from normalized_metrics nm
    left join cohort_stats cs on cs.cohort_month = nm.cohort_month
    left join user_quality_score uq on uq.user_id = nm.user_id
),
dedup as (
    select
        r.*,
        case
            when r.displayname is null or btrim(r.displayname) = '' then '(anonymous)'
            when position(' ' in r.displayname) > 0 then initcap(split_part(r.displayname, ' ', 1)) || ' ' || upper(substring(split_part(r.displayname, ' ', 2), 1, 1)) || '.'
            else initcap(r.displayname)
        end as displayname_fmt
    from ranked_users r
),
final_agg as (
    select
        d.*,
        case
            when (d.q_count + d.a_count) = 0 then null
            else round(cast(d.q_with_accepted as numeric) / nullif(d.q_count, 0), 4)
        end as accept_ratio,
        case
            when (d.q_count + d.a_count + d.c_count) = 0 then 'inactive'
            when d.quality_score >= (select percentile_cont(0.9) within group (order by quality_score) from ranked_users) then 'elite'
            when d.quality_score >= (select percentile_cont(0.75) within group (order by quality_score) from ranked_users) then 'high'
            when d.quality_score >= (select percentile_cont(0.5) within group (order by quality_score) from ranked_users) then 'medium'
            else 'low'
        end as quality_bucket
    from dedup d
)
select
    fa.user_id,
    fa.displayname_fmt as displayname,
    fa.cohort_month,
    fa.users_in_cohort,
    fa.reputation,
    fa.q_count, fa.a_count, fa.c_count,
    fa.q_views, fa.q_with_accepted,
    fa.upvotes_cast, fa.downvotes_cast, fa.bounty_total,
    fa.badge_cnt, fa.gold_cnt, fa.silver_cnt, fa.bronze_cnt,
    fa.related_links, fa.dup_links,
    fa.closed_q_count, fa.open_q_count,
    fa.active_months, fa.total_interactions,
    round(fa.activity_stddev, 2) as activity_stddev,
    fa.top_tag, fa.top_tag_posts,
    fa.quality_score, fa.quality_bucket,
    fa.cohort_rank, fa.global_dense_rank, fa.global_rownum,
    fa.accept_ratio,
    (
        select p.title
        from posts p
        where p.owneruserid = fa.user_id
          and p.posttypeid = 1
        order by coalesce(p.viewcount, 0) desc, p.id
        limit 1
    ) as top_question_title,
    exists (
        select 1
        from posthistory ph
        where ph.userid = fa.user_id
          and ph.posthistorytypeid in (4,5,6,7,8,9,24)
          and ph.postid is not null
          and ph.userid <> coalesce((select owneruserid from posts px where px.id = ph.postid), -1)
          and ph.creationdate >= (select min(creationdate) from recent_users)
    ) as edited_others_recently
from final_agg fa
where
    (
        fa.quality_bucket in ('elite','high')
        or (fa.quality_bucket = 'medium' and coalesce(fa.badge_cnt,0) >= 5)
        or (fa.quality_bucket = 'low' and fa.reputation > coalesce(fa.p50_rep, 0) and fa.active_months >= 3)
    )
  and (
        fa.top_tag is null
        or fa.top_tag = '(none)'
        or (
            fa.top_tag not ilike 'meta%' and fa.top_tag not ilike 'discussion%' and fa.top_tag not ilike 'off-topic%'
        )
      )
  and (fa.accept_ratio is null or fa.accept_ratio >= 0 or fa.q_count = 0)
order by fa.quality_score desc, fa.reputation desc, fa.user_id
limit 500;