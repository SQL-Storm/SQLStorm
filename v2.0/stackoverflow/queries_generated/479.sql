-- {"query": "479.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 4032} 
with
-- recent active users with weighted activity score
recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.location,
    u.creationdate,
    u.lastaccessdate,
    coalesce(u.upvotes - u.downvotes, 0) as net_votes,
    width_bucket(u.reputation, 0, 100000, 10) as rep_bucket,
    row_number() over (order by u.lastaccessdate desc, u.reputation desc) as rn,
    dense_rank() over (order by coalesce(u.location, 'Unknown')) as loc_rank
  from users u
  where u.lastaccessdate >= (select max(lastaccessdate) - interval '365 days' from users)
),
-- posts in the last 2 years with tag parsing and basic stats
recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.lastactivitydate,
    p.score,
    p.viewcount,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.acceptedanswerid,
    p.title,
    p.tags,
    substring(p.title from 1 for 100) as title_prefix,
    string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><') as tag_arr
  from posts p
  where p.creationdate >= (select coalesce(max(creationdate), now()) - interval '2 years' from posts)
),
-- tag exploded for recent posts
post_tags as (
  select
    rp.id as post_id,
    lower(trim(t)) as tag_name
  from recent_posts rp
  left join lateral unnest(coalesce(rp.tag_arr, array[]::varchar[])) as t on true
),
-- aggregate per user post metrics
user_post_metrics as (
  select
    rp.owneruserid as user_id,
    count(*) filter (where rp.posttypeid = 1) as questions,
    count(*) filter (where rp.posttypeid = 2) as answers,
    avg(nullif(rp.score,0)) as avg_score_nonzero,
    avg(rp.score) as avg_score,
    sum(coalesce(rp.viewcount,0)) as total_views,
    max(rp.viewcount) as max_views,
    count(*) filter (where rp.acceptedanswerid is not null) as accepted_q_count,
    sum(case when rp.posttypeid = 1 and rp.answercount >= 1 then 1 else 0 end) as answered_qs,
    count(*) filter (where rp.closeddate is not null) as closed_posts
  from recent_posts rp
  group by rp.owneruserid
),
-- windowed ranks for top posts per user
top_posts as (
  select
    rp.*,
    row_number() over (partition by rp.owneruserid order by rp.score desc nulls last, rp.viewcount desc nulls last, rp.creationdate desc) as score_rank,
    row_number() over (partition by rp.owneruserid order by rp.viewcount desc nulls last, rp.score desc nulls last, rp.creationdate desc) as view_rank
  from recent_posts rp
),
-- badges in window with counts by class and first/last dates
user_badges as (
  select
    b.userid as user_id,
    count(*) as badge_count,
    count(*) filter (where b.class = 1) as gold,
    count(*) filter (where b.class = 2) as silver,
    count(*) filter (where b.class = 3) as bronze,
    min(b.date) as first_badge,
    max(b.date) as last_badge
  from badges b
  where b.date >= (select coalesce(max(date), now()) - interval '3 years' from badges)
  group by b.userid
),
-- comment activity with sentiment-ish proxy via score and text length
user_comments as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    avg(coalesce(c.score,0)) as avg_comment_score,
    sum(case when c.score > 0 then 1 else 0 end) as pos_comments,
    sum(case when c.score < 0 then 1 else 0 end) as neg_comments,
    avg(length(c.text)) as avg_comment_len
  from comments c
  where c.creationdate >= (select coalesce(max(creationdate), now()) - interval '1 years' from comments)
  group by c.userid
),
-- votes cast by user (activity) and received on user's posts (impact)
user_votes_cast as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid = 5) as favorites_cast,
    count(*) filter (where v.votetypeid = 8) as bounties_started,
    sum(coalesce(v.bountyamount,0)) as bounty_given
  from votes v
  where v.creationdate >= (select coalesce(max(creationdate), now()) - interval '2 years' from votes)
  group by v.userid
),
user_votes_received as (
  select
    p.owneruserid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_received,
    count(*) filter (where v.votetypeid = 3) as downvotes_received,
    sum(coalesce(v.bountyamount,0)) as bounty_received
  from votes v
  join posts p on p.id = v.postid
  where p.creationdate >= (select coalesce(max(creationdate), now()) - interval '2 years' from posts)
  group by p.owneruserid
),
-- identify duplicate links and linked posts for influence measure
user_link_graph as (
  select
    p.owneruserid as user_id,
    count(*) filter (where pl.linktypeid = 1) as links_count,
    count(*) filter (where pl.linktypeid = 3) as dup_count,
    count(distinct pl.relatedpostid) as distinct_targets
  from postlinks pl
  join posts p on p.id = pl.postid
  where pl.creationdate >= (select coalesce(max(creationdate), now()) - interval '2 years' from postlinks)
  group by p.owneruserid
),
-- compute per-user tag diversity and top tag via window
user_tag_stats as (
  select
    pt_owner.owneruserid as user_id,
    count(distinct pt.tag_name) as tag_diversity,
    max(tag_total) filter (where rn = 1) as top_tag_count,
    min(tag_name) filter (where rn = 1) as top_tag_name
  from (
    select
      rp.owneruserid,
      pt.tag_name,
      count(*) as tag_total,
      row_number() over (partition by rp.owneruserid order by count(*) desc, min(rp.creationdate)) as rn
    from post_tags pt
    join recent_posts rp on rp.id = pt.post_id
    group by rp.owneruserid, pt.tag_name
  ) pt
  join (
    select distinct owneruserid from recent_posts
  ) pt_owner on pt_owner.owneruserid = pt.owneruserid
  group by pt_owner.owneruserid
),
-- extract close reasons via PostHistory JSON/text field for closed events
user_close_reasons as (
  select
    ph.userid as user_id,
    count(*) as close_events,
    count(*) filter (where ph.posthistorytypeid = 10 and ph.comment in ('101','102','103','104','105')) as close_with_reason_known
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
    and ph.creationdate >= (select coalesce(max(creationdate), now()) - interval '2 years' from posthistory)
  group by ph.userid
),
-- compute a decayed activity score with multiple inputs
activity as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.location,
    ru.creationdate,
    ru.lastaccessdate,
    ru.net_votes,
    ru.rep_bucket,
    upm.questions,
    upm.answers,
    upm.avg_score_nonzero,
    upm.avg_score,
    upm.total_views,
    upm.max_views,
    coalesce(ub.badge_count,0) as badge_count,
    coalesce(ub.gold,0) as gold,
    coalesce(ub.silver,0) as silver,
    coalesce(ub.bronze,0) as bronze,
    coalesce(uc.comment_count,0) as comment_count,
    coalesce(uc.avg_comment_score,0) as avg_comment_score,
    coalesce(uc.pos_comments,0) as pos_comments,
    coalesce(uc.neg_comments,0) as neg_comments,
    coalesce(uvc.upvotes_cast,0) as upvotes_cast,
    coalesce(uvc.downvotes_cast,0) as downvotes_cast,
    coalesce(uvc.favorites_cast,0) as favorites_cast,
    coalesce(uvc.bounties_started,0) as bounties_started,
    coalesce(uvc.bounty_given,0) as bounty_given,
    coalesce(uvr.upvotes_received,0) as upvotes_received,
    coalesce(uvr.downvotes_received,0) as downvotes_received,
    coalesce(uvr.bounty_received,0) as bounty_received,
    coalesce(ulg.links_count,0) as links_count,
    coalesce(ulg.dup_count,0) as dup_count,
    coalesce(ulg.distinct_targets,0) as distinct_targets,
    coalesce(uts.tag_diversity,0) as tag_diversity,
    uts.top_tag_name,
    coalesce(uts.top_tag_count,0) as top_tag_count,
    coalesce(ucr.close_events,0) as close_events,
    coalesce(ucr.close_with_reason_known,0) as close_with_reason_known
  from recent_users ru
  left join user_post_metrics upm on upm.user_id = ru.user_id
  left join user_badges ub on ub.user_id = ru.user_id
  left join user_comments uc on uc.user_id = ru.user_id
  left join user_votes_cast uvc on uvc.user_id = ru.user_id
  left join user_votes_received uvr on uvr.user_id = ru.user_id
  left join user_link_graph ulg on ulg.user_id = ru.user_id
  left join user_tag_stats uts on uts.user_id = ru.user_id
  left join user_close_reasons ucr on ucr.user_id = ru.user_id
),
-- correlated subquery to compute acceptance ratio per user
acceptance as (
  select
    u.id as user_id,
    coalesce((
      select count(*)::numeric / nullif(count(*) filter (where p.acceptedanswerid is not null),0)
      from posts p
      where p.posttypeid = 1 and p.owneruserid = u.id
    ), 0) as question_to_accepted_ratio,
    coalesce((
      select count(*) filter (where child.id = p.acceptedanswerid)
      from posts p
      join posts child on child.parentid = p.id
      where p.owneruserid = u.id and p.posttypeid = 1
    ), 0) as accepted_child_matches
  from users u
  where exists (select 1 from recent_posts rp where rp.owneruserid = u.id)
),
-- compute windowed z-scores for some metrics
scored as (
  select
    a.*,
    avg(a.avg_score) over () as mean_avg_score,
    stddev_pop(a.avg_score) over () as std_avg_score,
    avg(a.total_views) over () as mean_views,
    stddev_pop(a.total_views) over () as std_views,
    avg(a.upvotes_received - a.downvotes_received) over () as mean_net_received,
    stddev_pop(a.upvotes_received - a.downvotes_received) over () as std_net_received
  from activity a
),
-- final score with safeguards for null/stddev=0 and decay by recency
final_rank as (
  select
    s.*,
    coalesce((s.avg_score - s.mean_avg_score) / nullif(s.std_avg_score,0), 0) as z_avg_score,
    coalesce((s.total_views - s.mean_views) / nullif(s.std_views,0), 0) as z_views,
    coalesce(((s.upvotes_received - s.downvotes_received) - s.mean_net_received) / nullif(s.std_net_received,0), 0) as z_net_received,
    greatest(0.1, exp(-extract(epoch from (now() - s.lastaccessdate)) / 86400.0 / 180.0)) as recency_decay,
    case when s.questions + s.answers > 0 then s.answers::numeric / (s.questions + s.answers) else 0 end as answer_ratio
  from scored s
),
-- union a synthetic baseline user for set operator exercise
baseline as (
  select
    null::int as user_id, '<<baseline>>'::varchar as displayname, 0::int as reputation,
    'Nowhere'::varchar as location, now() - interval '5 years' as creationdate, now() - interval '5 years' as lastaccessdate,
    0::int as net_votes, 0::int as rep_bucket,
    0::bigint as questions, 0::bigint as answers, 0.0::numeric as avg_score_nonzero, 0.0::numeric as avg_score,
    0::bigint as total_views, 0::int as max_views, 0::int as badge_count, 0::int as gold, 0::int as silver, 0::int as bronze,
    0::bigint as comment_count, 0.0::numeric as avg_comment_score, 0::bigint as pos_comments, 0::bigint as neg_comments,
    0::bigint as upvotes_cast, 0::bigint as downvotes_cast, 0::bigint as favorites_cast, 0::bigint as bounties_started, 0::bigint as bounty_given,
    0::bigint as upvotes_received, 0::bigint as downvotes_received, 0::bigint as bounty_received,
    0::bigint as links_count, 0::bigint as dup_count, 0::bigint as distinct_targets,
    0::bigint as tag_diversity, null::varchar as top_tag_name, 0::bigint as top_tag_count,
    0::bigint as close_events, 0::bigint as close_with_reason_known,
    0.0::numeric as mean_avg_score, 0.0::numeric as std_avg_score, 0.0::numeric as mean_views, 0.0::numeric as std_views,
    0.0::numeric as mean_net_received, 0.0::numeric as std_net_received,
    0.0::numeric as z_avg_score, 0.0::numeric as z_views, 0.0::numeric as z_net_received, 1.0::numeric as recency_decay, 0.0::numeric as answer_ratio
)
select
  fr.user_id,
  fr.displayname,
  fr.reputation,
  coalesce(nullif(trim(fr.location), ''), 'Unknown') as location,
  fr.questions,
  fr.answers,
  fr.answer_ratio,
  fr.avg_score,
  fr.total_views,
  fr.upvotes_received,
  fr.downvotes_received,
  fr.badge_count,
  fr.gold,
  fr.silver,
  fr.bronze,
  fr.tag_diversity,
  coalesce(fr.top_tag_name, '(none)') as top_tag,
  fr.top_tag_count,
  fr.links_count,
  fr.dup_count,
  fr.distinct_targets,
  fr.comment_count,
  fr.avg_comment_score,
  fr.pos_comments,
  fr.neg_comments,
  fr.close_events,
  fr.close_with_reason_known,
  fr.recency_decay,
  fr.z_avg_score,
  fr.z_views,
  fr.z_net_received,
  coalesce(ac.question_to_accepted_ratio, 0) as question_to_accepted_ratio,
  coalesce(ac.accepted_child_matches, 0) as accepted_child_matches,
  -- composite final score
  round((
    (fr.z_avg_score * 0.35) +
    (fr.z_views * 0.25) +
    (fr.z_net_received * 0.25) +
    (least(3.0, ln(1 + fr.badge_count)) * 0.10) +
    (least(2.0, ln(1 + fr.tag_diversity)) * 0.05)
  ) * fr.recency_decay, 6) as final_activity_score,
  -- illustrative complex predicate flags
  case
    when fr.reputation >= 10000 and fr.answers >= 50 and (fr.upvotes_received - fr.downvotes_received) > 500 then 'elite'
    when fr.reputation between 2000 and 9999 and fr.answers >= 10 then 'strong'
    when fr.questions >= 10 and fr.answers = 0 then 'question-heavy'
    when fr.answers >= 10 and fr.questions = 0 then 'answer-heavy'
    else 'mixed'
  end as profile_bucket
from (
  select * from final_rank
  union all
  select * from baseline
) fr
left join acceptance ac on ac.user_id = fr.user_id
where
  -- include either users with meaningful activity or the synthetic baseline
  (
    coalesce(fr.answers,0) + coalesce(fr.questions,0) + coalesce(fr.comment_count,0) +
    coalesce(fr.upvotes_cast,0) + coalesce(fr.downvotes_cast,0)
  ) > 0
  or fr.user_id is null
qualify
  -- keep top-N by final score per location, with ties
  row_number() over (
    partition by coalesce(nullif(trim(fr.location), ''), 'Unknown')
    order by (
      (fr.z_avg_score * 0.35) +
      (fr.z_views * 0.25) +
      (fr.z_net_received * 0.25) +
      (least(3.0, ln(1 + fr.badge_count)) * 0.10) +
      (least(2.0, ln(1 + fr.tag_diversity)) * 0.05)
    ) * fr.recency_decay desc nulls last
  ) <= 50
order by final_activity_score desc nulls last, fr.reputation desc nulls last, fr.displayname asc;