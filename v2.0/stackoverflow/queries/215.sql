with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
    date_trunc('month', u.creationdate) as cohort_month,
    row_number() over (order by u.creationdate desc, u.id desc) as rn_newest
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    sum(coalesce(p.score,0)) as total_score,
    avg(nullif(p.score,0)) as avg_nonzero_score,
    max(p.viewcount) as max_views,
    count(*) filter (where p.closeddate is not null) as closed_count,
    count(distinct case when p.posttypeid = 1 then p.id end) as distinct_questions,
    count(distinct case when p.posttypeid = 2 then p.parentid end) as distinct_answered_questions
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
comment_cte as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    sum(coalesce(c.score,0)) as comment_score,
    max(c.creationdate) as last_comment_at
  from comments c
  where c.userid is not null
  group by c.userid
),
badge_rollup as (
  select
    b.userid as user_id,
    count(*) as badge_count,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    min(b.date) as first_badge_at,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
vote_agg as (
  select
    v.userid as voter_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    sum(coalesce(v.bountyamount,0)) as bounty_total_cast,
    min(v.creationdate) as first_vote_at,
    max(v.creationdate) as last_vote_at
  from votes v
  where v.userid is not null
  group by v.userid
),
post_vote_received as (
  select
    p.owneruserid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_received,
    count(*) filter (where v.votetypeid = 3) as downvotes_received,
    sum(coalesce(v.bountyamount,0)) as bounties_received
  from posts p
  left join votes v on v.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
question_tag_counts as (
  select
    p.owneruserid as user_id,
    lower(trim(t)) as tag_name,
    count(*) as tag_q_count
  from posts p
  cross join lateral unnest(
    case
      when p.posttypeid = 1 and p.tags is not null and length(p.tags) > 2
      then string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
      else array[]::varchar[]
    end
  ) as t
  where p.owneruserid is not null
  group by p.owneruserid, lower(trim(t))
),
top3_tags as (
  select
    user_id,
    array_agg(tag_name order by tag_q_count desc, tag_name asc) as top_tags_arr,
    array_agg(tag_q_count order by tag_q_count desc, tag_name asc) as top_counts_arr
  from question_tag_counts
  group by user_id
),
dup_link_stats as (
  select
    p.owneruserid as user_id,
    count(*) filter (where pl.linktypeid = 3 and pl.postid = p.id) as marked_duplicate_of_others,
    count(*) filter (where pl.linktypeid = 3 and pl.relatedpostid = p.id) as others_marked_duplicate_of_mine
  from posts p
  left join postlinks pl
    on pl.postid = p.id or pl.relatedpostid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
edits_cte as (
  select
    ph.userid as user_id,
    count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
    count(*) filter (where ph.posthistorytypeid in (10)) as closed_events,
    count(*) filter (where ph.posthistorytypeid in (11)) as reopened_events,
    count(*) filter (where ph.posthistorytypeid in (52)) as hot_selected_events
  from posthistory ph
  where ph.userid is not null
  group by ph.userid
),
activity_union as (
  select ua.user_id, 'posts' as src, ua.q_count + ua.a_count as activity_units, ua.total_score as score_impact
  from user_activity ua
  union all
  select c.user_id, 'comments', c.comment_count, c.comment_score
  from comment_cte c
  union all
  select v.voter_id, 'votes', coalesce(v.upvotes_cast,0) + coalesce(v.downvotes_cast,0), 0
  from vote_agg v
),
activity_rank as (
  select
    user_id,
    sum(activity_units) as total_units,
    sum(score_impact) as total_score_impact,
    rank() over (order by sum(activity_units) desc nulls last, sum(score_impact) desc nulls last) as activity_rank
  from activity_union
  group by user_id
),
null_logic as (
  select
    u.id as user_id,
    case
      when u.displayname is null and p.owneruserid is not null then 'anon-owner'
      when u.displayname is null then 'anon'
      else u.displayname
    end as name_or_anon,
    u.displayname,
    p.owneruserid
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id, u.displayname, p.owneruserid
),
cohort_stats as (
  select
    ru.cohort_month,
    count(distinct ru.user_id) as users_in_cohort,
    -- replace percentile_cont within group (ordered-set) with approximate using percentile_disc on aggregated values
    percentile_disc(0.5) within group (order by coalesce(ua.q_count,0) + coalesce(ua.a_count,0)) as p50_posts_created,
    percentile_disc(0.9) within group (order by coalesce(pvr.upvotes_received,0) - coalesce(pvr.downvotes_received,0)) as p90_net_votes_received
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join post_vote_received pvr on pvr.user_id = ru.user_id
  group by ru.cohort_month
),
qualified_users as (
  select
    ru.user_id
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join comment_cte c on c.user_id = ru.user_id
  where coalesce(ua.q_count,0) + coalesce(ua.a_count,0) >= 5
    and coalesce(c.comment_count,0) >= 3
    and (ru.websiteurl_norm is not null or ru.location is not null)
),
final_scores as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    coalesce(ua.q_count,0) as q_count,
    coalesce(ua.a_count,0) as a_count,
    coalesce(ua.total_score,0) as total_post_score,
    coalesce(ua.avg_nonzero_score,0) as avg_nonzero_score,
    coalesce(ua.max_views,0) as max_views,
    coalesce(c.comment_count,0) as comment_count,
    coalesce(c.comment_score,0) as comment_score,
    coalesce(br.badge_count,0) as badge_count,
    coalesce(br.gold_badges,0) as gold_badges,
    coalesce(br.silver_badges,0) as silver_badges,
    coalesce(br.bronze_badges,0) as bronze_badges,
    coalesce(va.upvotes_cast,0) as upvotes_cast,
    coalesce(va.downvotes_cast,0) as downvotes_cast,
    coalesce(va.bounty_total_cast,0) as bounty_total_cast,
    coalesce(pvr.upvotes_received,0) as upvotes_received,
    coalesce(pvr.downvotes_received,0) as downvotes_received,
    coalesce(pvr.bounties_received,0) as bounties_received,
    coalesce(dls.marked_duplicate_of_others,0) as dup_of_others,
    coalesce(dls.others_marked_duplicate_of_mine,0) as dup_of_mine,
    coalesce(e.edit_events,0) as edit_events,
    coalesce(e.closed_events,0) as closed_events,
    coalesce(e.reopened_events,0) as reopened_events,
    coalesce(e.hot_selected_events,0) as hot_selected_events,
    coalesce(ar.total_units,0) as total_activity_units,
    coalesce(ar.total_score_impact,0) as total_score_impact,
    ar.activity_rank,
    case
      when coalesce(pvr.upvotes_received,0) + coalesce(pvr.downvotes_received,0) = 0 then null
      else (coalesce(pvr.upvotes_received,0) - coalesce(pvr.downvotes_received,0))
           / nullif((coalesce(pvr.upvotes_received,0) + coalesce(pvr.downvotes_received,0)),0)
    end as net_vote_ratio,
    (case
       when t3.top_tags_arr is null then ''
       else array_to_string( (case when array_length(t3.top_tags_arr,1) > 3 then t3.top_tags_arr[1:3] else t3.top_tags_arr end), ',')
     end) as top3_tags,
    (case
       when t3.top_counts_arr is null then ''
       else array_to_string( (case when array_length(t3.top_counts_arr,1) > 3 then t3.top_counts_arr[1:3] else t3.top_counts_arr end), ',')
     end) as top3_tag_counts
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join comment_cte c on c.user_id = ru.user_id
  left join badge_rollup br on br.user_id = ru.user_id
  left join vote_agg va on va.voter_id = ru.user_id
  left join post_vote_received pvr on pvr.user_id = ru.user_id
  left join dup_link_stats dls on dls.user_id = ru.user_id
  left join edits_cte e on e.user_id = ru.user_id
  left join activity_rank ar on ar.user_id = ru.user_id
  left join top3_tags t3 on t3.user_id = ru.user_id
  where ru.user_id in (select user_id from qualified_users)
),
ranked as (
  select
    fs.*,
    dense_rank() over (
      order by
        (coalesce(fs.total_activity_units,0)
         + coalesce(fs.total_post_score,0)
         + 5 * coalesce(fs.gold_badges,0)
         + 3 * coalesce(fs.silver_badges,0)
         + 1 * coalesce(fs.bronze_badges,0)
         + coalesce(fs.bounties_received,0)
         - 2 * coalesce(fs.dup_of_others,0)
        ) desc nulls last,
        coalesce(fs.net_vote_ratio, -1) desc nulls last,
        fs.reputation desc nulls last,
        fs.user_id asc
    ) as dense_rank_overall
  from final_scores fs
),
-- compute cohort_percentile by aggregating per-cohort values and joining back; ordered-set aggregate removed from window usage
cohort_window_p75 as (
  select
    r.cohort_month,
    percentile_disc(0.75) within group (order by r.total_activity_units) as cohort_p75_units
  from ranked r
  group by r.cohort_month
),
window_summaries as (
  select
    r.user_id,
    r.displayname,
    r.reputation,
    r.cohort_month,
    r.q_count,
    r.a_count,
    r.total_post_score,
    r.avg_nonzero_score,
    r.max_views,
    r.comment_count,
    r.comment_score,
    r.badge_count,
    r.gold_badges,
    r.silver_badges,
    r.bronze_badges,
    r.upvotes_cast,
    r.downvotes_cast,
    r.bounty_total_cast,
    r.upvotes_received,
    r.downvotes_received,
    r.bounties_received,
    r.dup_of_others,
    r.dup_of_mine,
    r.edit_events,
    r.closed_events,
    r.reopened_events,
    r.hot_selected_events,
    r.total_activity_units,
    r.total_score_impact,
    r.activity_rank,
    r.net_vote_ratio,
    r.top3_tags,
    r.top3_tag_counts,
    r.dense_rank_overall,
    sum(r.total_activity_units) over (partition by r.cohort_month) as cohort_total_units,
    avg(r.total_post_score) over (partition by r.cohort_month) as cohort_avg_post_score,
    cw.cohort_p75_units,
    lag(r.total_activity_units) over (partition by r.cohort_month order by r.dense_rank_overall) as prev_units_in_cohort,
    lead(r.total_activity_units) over (partition by r.cohort_month order by r.dense_rank_overall) as next_units_in_cohort
  from ranked r
  left join cohort_window_p75 cw on cw.cohort_month = r.cohort_month
)
select
  ws.user_id,
  ws.displayname,
  ws.reputation,
  ws.cohort_month,
  ws.q_count,
  ws.a_count,
  ws.total_post_score,
  ws.avg_nonzero_score,
  ws.max_views,
  ws.comment_count,
  ws.comment_score,
  ws.badge_count,
  ws.gold_badges,
  ws.silver_badges,
  ws.bronze_badges,
  ws.upvotes_cast,
  ws.downvotes_cast,
  ws.bounty_total_cast,
  ws.upvotes_received,
  ws.downvotes_received,
  ws.bounties_received,
  ws.dup_of_others,
  ws.dup_of_mine,
  ws.edit_events,
  ws.closed_events,
  ws.reopened_events,
  ws.hot_selected_events,
  ws.total_activity_units,
  ws.total_score_impact,
  ws.activity_rank,
  ws.net_vote_ratio,
  ws.top3_tags,
  ws.top3_tag_counts,
  ws.dense_rank_overall,
  ws.cohort_total_units,
  ws.cohort_avg_post_score,
  ws.cohort_p75_units,
  ws.prev_units_in_cohort,
  ws.next_units_in_cohort
from window_summaries ws
where ws.dense_rank_overall <= 200
order by ws.dense_rank_overall, ws.user_id;