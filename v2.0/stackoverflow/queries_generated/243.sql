-- {"query": "243.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3706} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as website_norm,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
    select
        u.user_id,
        count(distinct p.id) filter (where p.posttypeid in (1,2)) as total_posts,
        count(*) filter (where p.posttypeid = 1) as questions,
        count(*) filter (where p.posttypeid = 2) as answers,
        sum(greatest(p.score, 0)) as nonneg_post_score,
        sum(coalesce(p.viewcount,0)) as total_views,
        avg(nullif(p.score,0)) as avg_nonzero_post_score,
        max(p.lastactivitydate) as last_post_activity
    from recent_users u
    left join posts p
      on p.owneruserid = u.user_id
    group by u.user_id
),
user_comment_stats as (
    select
        u.user_id,
        count(c.id) as comment_count,
        sum(coalesce(c.score,0)) as comment_score,
        min(c.creationdate) as first_comment_at,
        max(c.creationdate) as last_comment_at,
        percentile_disc(0.9) within group (order by coalesce(c.score,0)) as p90_comment_score
    from recent_users u
    left join comments c
      on c.userid = u.user_id
    group by u.user_id
),
user_badges as (
    select
        u.user_id,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges,
        count(b.id) as total_badges,
        max(b.date) as last_badge_at
    from recent_users u
    left join badges b
      on b.userid = u.user_id
    group by u.user_id
),
question_details as (
    select
        p.owneruserid as user_id,
        p.id as question_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.acceptedanswerid,
        p.closeddate,
        string_to_array(substring(p.tags, 2, length(p.tags)-2), '><') as tag_arr,
        case when p.closeddate is not null then 1 else 0 end as is_closed
    from posts p
    where p.posttypeid = 1
),
answer_details as (
    select
        a.owneruserid as user_id,
        a.id as answer_id,
        a.parentid as question_id,
        a.creationdate,
        a.score as answer_score
    from posts a
    where a.posttypeid = 2
),
q_agg as (
    select
        q.user_id,
        count(*) as q_count,
        sum(coalesce(q.viewcount,0)) as q_views,
        avg(nullif(q.score,0)) as avg_nonzero_q_score,
        sum(case when q.acceptedanswerid is not null then 1 else 0 end) as accepted_q_count,
        sum(q.is_closed) as closed_q_count,
        count(*) filter (where coalesce(array_length(q.tag_arr,1),0) >= 5) as q_with_5plus_tags
    from question_details q
    group by q.user_id
),
a_agg as (
    select
        a.user_id,
        count(*) as a_count,
        avg(a.answer_score) as avg_a_score,
        count(*) filter (where a.answer_score > 0) as pos_a_count
    from answer_details a
    group by a.user_id
),
votes_per_post as (
    select
        v.postid,
        sum(case when vt.name = 'UpMod (AKA upvote)' or v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when vt.name = 'DownMod (AKA downvote)' or v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    left join votetypes vt on vt.id = v.votetypeid
    group by v.postid
),
user_vote_agg as (
    select
        p.owneruserid as user_id,
        sum(coalesce(vp.upvotes,0)) as post_upvotes,
        sum(coalesce(vp.downvotes,0)) as post_downvotes,
        sum(coalesce(vp.favorites,0)) as post_favorites,
        sum(coalesce(vp.bounty_total,0)) as post_bounty_total
    from posts p
    left join votes_per_post vp on vp.postid = p.id
    group by p.owneruserid
),
hot_question_history as (
    select
        ph.postid,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 52) as first_hot_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 53) as last_removed_hot_at,
        count(*) filter (where ph.posthistorytypeid = 52) as hot_count
    from posthistory ph
    where ph.posthistorytypeid in (52,53)
    group by ph.postid
),
dup_links as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as master_post_id,
        count(*) as dup_link_count
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
tag_exploded as (
    select
        q.user_id,
        lower(trim(t)) as tag_name
    from question_details q
    cross join lateral unnest(q.tag_arr) as t
),
user_top_tags as (
    select user_id, tag_name, tag_cnt,
           row_number() over (partition by user_id order by tag_cnt desc, tag_name) as rn
    from (
        select user_id, tag_name, count(*) as tag_cnt
        from tag_exploded
        group by user_id, tag_name
    ) s
),
user_top3_tags as (
    select user_id,
           array_agg(tag_name order by rn) filter (where rn <= 3) as top3_tags
    from user_top_tags
    where rn <= 3
    group by user_id
),
user_quality_score as (
    select
        u.user_id,
        coalesce(ua.nonneg_post_score,0)
        + coalesce(ua.avg_nonzero_post_score,0) * 10
        + coalesce(qa.accepted_q_count,0) * 25
        + coalesce(aa.pos_a_count,0) * 2
        + least(coalesce(uv.post_upvotes,0) - coalesce(uv.post_downvotes,0), 1000) * 0.5
        + coalesce(uv.post_bounty_total,0) * 0.1
        + case when coalesce(qa.closed_q_count,0) > 5 then -50 else 0 end
        + case when coalesce(ua.total_posts,0) = 0 then -100 else 0 end
        as quality_score
    from recent_users u
    left join user_activity ua on ua.user_id = u.user_id
    left join q_agg qa on qa.user_id = u.user_id
    left join a_agg aa on aa.user_id = u.user_id
    left join user_vote_agg uv on uv.user_id = u.user_id
),
cohort_stats as (
    select
        cohort_month,
        count(*) as users_in_cohort,
        percentile_cont(0.5) within group (order by quality_score) as median_quality,
        avg(quality_score) as avg_quality
    from recent_users u
    left join user_quality_score qs on qs.user_id = u.user_id
    group by cohort_month
),
post_engagement as (
    select
        p.id as post_id,
        p.posttypeid,
        p.owneruserid as user_id,
        coalesce(vp.upvotes,0) as upvotes,
        coalesce(vp.downvotes,0) as downvotes,
        coalesce(vp.favorites,0) as favorites,
        (coalesce(vp.upvotes,0) - coalesce(vp.downvotes,0))::numeric / nullif((coalesce(vp.upvotes,0) + coalesce(vp.downvotes,0)),0) as vote_ratio,
        greatest(0, coalesce(p.viewcount,0)) as views,
        coalesce(hq.hot_count,0) as times_hot
    from posts p
    left join votes_per_post vp on vp.postid = p.id
    left join hot_question_history hq on hq.postid = p.id
),
user_engagement_rank as (
    select
        pe.user_id,
        avg(coalesce(pe.vote_ratio, 0)) as avg_vote_ratio,
        sum(pe.views) as total_views,
        sum(pe.times_hot) as total_times_hot,
        rank() over (order by sum(pe.views) desc, avg(coalesce(pe.vote_ratio, 0)) desc) as view_rank
    from post_engagement pe
    group by pe.user_id
),
normalized_locations as (
    select
        u.user_id,
        case
            when u.location ilike '%united states%' or u.location ilike '%usa%' or u.location ilike '%us%' then 'USA'
            when u.location ilike '%india%' then 'India'
            when u.location ilike '%united kingdom%' or u.location ilike '%uk%' or u.location ilike '%england%' then 'UK'
            when u.location ilike '%germany%' then 'Germany'
            when u.location ilike '%canada%' then 'Canada'
            when u.location is null or trim(u.location) = '' then 'Unknown'
            else 'Other'
        end as country_bucket
    from recent_users u
),
closed_reasons as (
    select
        q.postid as post_id,
        max(case when try_cast(ph.comment as int) in (1,101) then 'Duplicate'
                 when try_cast(ph.comment as int) in (2,102) then 'Off-topic'
                 when try_cast(ph.comment as int) in (103) then 'Needs details or clarity'
                 when try_cast(ph.comment as int) in (104) then 'Needs more focus'
                 when try_cast(ph.comment as int) in (105) then 'Opinion-based'
                 else 'Other' end) as close_bucket
    from posthistory ph
    join posts q on q.id = ph.postid and q.posttypeid = 1
    where ph.posthistorytypeid = 10
    group by q.postid
),
dup_master_counts as (
    select
        m.owneruserid as user_id,
        count(distinct d.dup_post_id) as dup_marked_against_count
    from dup_links d
    join posts m on m.id = d.master_post_id
    group by m.owneruserid
),
final as (
    select
        u.user_id,
        u.displayname,
        u.website_norm,
        nl.country_bucket,
        u.reputation,
        u.cohort_month,
        coalesce(ua.total_posts,0) as total_posts,
        coalesce(ua.questions,0) as questions,
        coalesce(ua.answers,0) as answers,
        coalesce(ucs.comment_count,0) as comment_count,
        coalesce(ub.total_badges,0) as total_badges,
        coalesce(ub.gold_badges,0) as gold_badges,
        coalesce(qa.q_count,0) as q_count,
        coalesce(aa.a_count,0) as a_count,
        coalesce(qa.q_views,0) as q_views,
        coalesce(qa.accepted_q_count,0) as accepted_q_count,
        coalesce(qa.closed_q_count,0) as closed_q_count,
        coalesce(uv.post_upvotes,0) as post_upvotes,
        coalesce(uv.post_downvotes,0) as post_downvotes,
        coalesce(uv.post_favorites,0) as post_favorites,
        coalesce(uv.post_bounty_total,0) as post_bounty_total,
        coalesce(uer.avg_vote_ratio,0) as avg_vote_ratio,
        coalesce(uer.total_views,0) as total_views,
        coalesce(uer.total_times_hot,0) as total_times_hot,
        coalesce(dmc.dup_marked_against_count,0) as dup_marked_against_count,
        coalesce(array_to_string(utt.top3_tags, ', '), 'none') as top_tags,
        qs.quality_score,
        lag(qs.quality_score) over (partition by nl.country_bucket order by u.cohort_month, u.user_id) as prev_quality_in_bucket,
        row_number() over (order by qs.quality_score desc, coalesce(uer.view_rank, 1e9)) as global_rownum
    from recent_users u
    left join user_activity ua on ua.user_id = u.user_id
    left join user_comment_stats ucs on ucs.user_id = u.user_id
    left join user_badges ub on ub.user_id = u.user_id
    left join q_agg qa on qa.user_id = u.user_id
    left join a_agg aa on aa.user_id = u.user_id
    left join user_vote_agg uv on uv.user_id = u.user_id
    left join user_engagement_rank uer on uer.user_id = u.user_id
    left join user_quality_score qs on qs.user_id = u.user_id
    left join normalized_locations nl on nl.user_id = u.user_id
    left join user_top3_tags utt on utt.user_id = u.user_id
    left join dup_master_counts dmc on dmc.user_id = u.user_id
),
country_rollup as (
    select
        country_bucket,
        count(*) as users,
        avg(quality_score) as avg_quality,
        stddev_pop(quality_score) as std_quality,
        max(quality_score) as max_quality
    from final
    group by country_bucket
),
ranked as (
    select
        f.*,
        dense_rank() over (partition by f.country_bucket order by f.quality_score desc) as country_rank,
        percentile_disc(0.75) within group (order by f.quality_score) over (partition by f.country_bucket) as p75_country_quality
    from final f
)
select
    r.user_id,
    r.displayname,
    r.country_bucket,
    r.reputation,
    r.cohort_month,
    r.total_posts,
    r.questions,
    r.answers,
    r.comment_count,
    r.total_badges,
    r.gold_badges,
    r.q_count,
    r.a_count,
    r.q_views,
    r.accepted_q_count,
    r.closed_q_count,
    r.post_upvotes,
    r.post_downvotes,
    r.post_favorites,
    r.post_bounty_total,
    r.avg_vote_ratio,
    r.total_views,
    r.total_times_hot,
    r.dup_marked_against_count,
    r.top_tags,
    r.quality_score,
    r.prev_quality_in_bucket,
    r.global_rownum,
    r.country_rank,
    cr.users as country_users,
    cr.avg_quality as country_avg_quality,
    cr.std_quality as country_std_quality,
    cr.max_quality as country_max_quality,
    r.p75_country_quality,
    case when r.quality_score >= r.p75_country_quality then 1 else 0 end as is_top_quartile_in_country
from ranked r
left join country_rollup cr using (country_bucket)
where (
        r.quality_score > 0
        and coalesce(r.total_posts,0) + coalesce(r.comment_count,0) > 0
        and (r.country_bucket <> 'Unknown' or r.reputation > 1000)
      )
  and not exists (
        select 1
        from posts p
        where p.owneruserid = r.user_id
          and p.posttypeid = 1
          and p.closeddate is not null
          and p.creationdate >= current_date - interval '7 days'
          and exists (
              select 1
              from closed_reasons cr2
              where cr2.post_id = p.id
                and cr2.close_bucket = 'Off-topic'
          )
      )
order by r.quality_score desc, r.total_views desc, r.post_upvotes - r.post_downvotes desc
fetch first 250 rows with ties;