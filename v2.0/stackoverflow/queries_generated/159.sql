-- {"query": "159.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3122} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    count(b.id) filter (where b.class = 1) as gold_badges,
    count(b.id) filter (where b.class = 2) as silver_badges,
    count(b.id) filter (where b.class = 3) as bronze_badges,
    count(*) as total_badges,
    max(b.date) as last_badge_date
  from users u
  left join badges b
    on b.userid = u.id
  where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '365 days' from users)
  group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.websiteurl
),
question_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as questions,
    sum(p.viewcount) filter (where p.posttypeid = 1) as question_views,
    count(*) filter (where p.posttypeid = 2) as answers,
    sum(p.score) filter (where p.posttypeid in (1,2)) as total_score,
    count(*) filter (where p.posttypeid = 1 and p.acceptedanswerid is not null) as accepted_questions,
    count(*) filter (
      where p.posttypeid = 1 and p.closeddate is not null
    ) as closed_questions,
    max(p.lastactivitydate) as last_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
votes_agg as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid = 5) as favorites_cast,
    count(*) filter (where v.votetypeid in (8,9)) as bounty_events,
    sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_amount_total,
    max(v.creationdate) as last_vote_date
  from votes v
  where v.userid is not null
  group by v.userid
),
comments_agg as (
  select
    c.userid as user_id,
    count(*) as comments_made,
    sum(c.score) as comment_score,
    max(c.creationdate) as last_comment_date,
    avg(length(c.text)) as avg_comment_len
  from comments c
  where c.userid is not null
  group by c.userid
),
tag_usage as (
  select
    p.owneruserid as user_id,
    unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tagname
  from posts p
  where p.posttypeid = 1 and p.tags is not null and p.owneruserid is not null
),
top_tag_per_user as (
  select user_id, tagname
  from (
    select
      tu.user_id,
      tu.tagname,
      count(*) as tag_count,
      row_number() over (partition by tu.user_id order by count(*) desc, min(tu.tagname)) as rn
    from tag_usage tu
    group by tu.user_id, tu.tagname
  ) s
  where rn = 1
),
dup_closures as (
  select
    ph.userid as moderator_user_id,
    count(*) as duplicate_closes,
    max(ph.creationdate) as last_dup_close
  from posthistory ph
  where ph.posthistorytypeid = 10
    and coalesce(nullif(ph.comment, ''), '0') ~ '^[0-9]+$'
    and cast(ph.comment as int) in (1, 101)
    and ph.userid is not null
  group by ph.userid
),
link_graph as (
  select
    pl.postid,
    pl.relatedpostid,
    pl.linktypeid,
    pl.creationdate,
    case when pl.linktypeid = 3 then 1 else 0 end as is_duplicate
  from postlinks pl
),
post_interactions as (
  select
    p.owneruserid as user_id,
    count(distinct lg.relatedpostid) filter (where lg.is_duplicate = 1) as dup_links_out,
    count(distinct lg.postid) filter (where lg.is_duplicate = 1) as dup_links_in, -- symmetric count via reversed perspective
    count(*) filter (where lg.linktypeid = 1) as related_links
  from posts p
  left join link_graph lg
    on lg.postid = p.id or lg.relatedpostid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
user_quality as (
  select
    qa.user_id,
    case
      when qa.answers > 0 then round(qa.total_score::numeric / nullif(qa.answers,0), 3)
      else null
    end as avg_answer_score,
    case
      when qa.questions > 0 then round(qa.question_views::numeric / nullif(qa.questions,0), 3)
      else null
    end as avg_question_views,
    round(coalesce(qa.total_score,0)::numeric / greatest(qa.questions + qa.answers, 1), 3) as avg_post_score
  from question_activity qa
),
editors as (
  select
    ph.userid as user_id,
    count(*) filter (where ph.posthistorytypeid in (4,5,6,24)) as edits_made,
    count(distinct ph.postid) filter (where ph.posthistorytypeid in (4,5,6,24)) as edited_posts,
    max(ph.creationdate) as last_edit_date
  from posthistory ph
  where ph.userid is not null
  group by ph.userid
),
user_rank as (
  select
    ru.user_id,
    dense_rank() over (order by ru.total_badges desc, ru.reputation desc, ru.creationdate) as prestige_rank,
    ntile(10) over (order by coalesce(qa.total_score,0) desc nulls last) as score_decile
  from recent_users ru
  left join question_activity qa on qa.user_id = ru.user_id
),
activity_recency as (
  select
    u.id as user_id,
    greatest(
      coalesce(qa.last_activity, 'epoch'::timestamp),
      coalesce(v.last_vote_date, 'epoch'::timestamp),
      coalesce(c.last_comment_date, 'epoch'::timestamp),
      coalesce(e.last_edit_date, 'epoch'::timestamp),
      u.lastaccessdate
    ) as last_seen_any
  from users u
  left join question_activity qa on qa.user_id = u.id
  left join votes_agg v on v.user_id = u.id
  left join comments_agg c on c.user_id = u.id
  left join editors e on e.user_id = u.id
),
outlier_flags as (
  select
    ru.user_id,
    (coalesce(qa.answers,0) > 0 and coalesce(uq.avg_answer_score,0) > (select avg(score) from posts where posttypeid = 2)) as high_answer_quality,
    (coalesce(qa.questions,0) > 0 and coalesce(uq.avg_question_views,0) > (select avg(viewcount) from posts where posttypeid = 1)) as high_question_visibility,
    (coalesce(v.bounty_amount_total,0) > (select coalesce(percentile_cont(0.95) within group (order by coalesce(bountyamount,0)),0) from votes where votetypeid in (8,9))) as top_bounty_user
  from recent_users ru
  left join question_activity qa on qa.user_id = ru.user_id
  left join user_quality uq on uq.user_id = ru.user_id
  left join votes_agg v on v.user_id = ru.user_id
),
ranked_users as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.location,
    ru.websiteurl,
    ru.total_badges,
    ru.gold_badges,
    ru.silver_badges,
    ru.bronze_badges,
    qa.questions,
    qa.answers,
    qa.total_score,
    qa.accepted_questions,
    qa.closed_questions,
    uq.avg_answer_score,
    uq.avg_question_views,
    uq.avg_post_score,
    coalesce(v.upvotes_cast,0) as upvotes_cast,
    coalesce(v.downvotes_cast,0) as downvotes_cast,
    coalesce(v.favorites_cast,0) as favorites_cast,
    coalesce(v.bounty_events,0) as bounty_events,
    coalesce(v.bounty_amount_total,0) as bounty_amount_total,
    coalesce(c.comments_made,0) as comments_made,
    coalesce(c.comment_score,0) as comment_score,
    coalesce(c.avg_comment_len,0) as avg_comment_len,
    coalesce(e.edits_made,0) as edits_made,
    coalesce(e.edited_posts,0) as edited_posts,
    coalesce(pi.dup_links_out,0) as dup_links_out,
    coalesce(pi.dup_links_in,0) as dup_links_in,
    coalesce(pi.related_links,0) as related_links,
    tt.tagname as top_tag,
    ur.prestige_rank,
    ur.score_decile,
    ar.last_seen_any,
    dc.duplicate_closes
  from recent_users ru
  left join question_activity qa on qa.user_id = ru.user_id
  left join user_quality uq on uq.user_id = ru.user_id
  left join votes_agg v on v.user_id = ru.user_id
  left join comments_agg c on c.user_id = ru.user_id
  left join editors e on e.user_id = ru.user_id
  left join post_interactions pi on pi.user_id = ru.user_id
  left join top_tag_per_user tt on tt.user_id = ru.user_id
  left join user_rank ur on ur.user_id = ru.user_id
  left join activity_recency ar on ar.user_id = ru.user_id
  left join dup_closures dc on dc.moderator_user_id = ru.user_id
),
normalized as (
  select
    r.*,
    case when r.questions is null or r.questions = 0 then null else round((r.accepted_questions::numeric / r.questions) * 100, 2) end as question_accept_rate_pct,
    case when r.questions is null or r.questions = 0 then null else round((r.closed_questions::numeric / r.questions) * 100, 2) end as question_close_rate_pct,
    round((coalesce(r.upvotes_cast,0) - coalesce(r.downvotes_cast,0))::numeric / greatest(coalesce(r.upvotes_cast,0)+coalesce(r.downvotes_cast,0),1), 3) as vote_polarity,
    case when r.total_score is null then 0 else r.total_score end
      + coalesce(r.comment_score,0)
      + least(coalesce(r.bounty_amount_total,0) / 50, 100) as engagement_score,
    case
      when r.top_tag is null then 'unknown'
      when length(r.top_tag) <= 3 then 'short'
      when length(r.top_tag) between 4 and 7 then 'medium'
      else 'long'
    end as top_tag_len_bucket
  from ranked_users r
),
thresholds as (
  select
    coalesce(percentile_cont(0.90) within group (order by engagement_score), 0) as p90_engagement,
    coalesce(percentile_cont(0.75) within group (order by coalesce(avg_post_score,0)), 0) as p75_quality
  from normalized
),
final_scored as (
  select
    n.*,
    (case when n.engagement_score >= t.p90_engagement then 1 else 0 end) as is_high_engagement,
    (case when coalesce(n.avg_post_score,0) >= t.p75_quality then 1 else 0 end) as is_high_quality,
    rank() over (
      order by
        coalesce(n.engagement_score,0) desc,
        coalesce(n.avg_post_score,0) desc,
        n.reputation desc,
        n.total_badges desc,
        n.last_seen_any desc
    ) as global_rank
  from normalized n
  cross join thresholds t
)
select
  fs.global_rank,
  fs.user_id,
  coalesce(nullif(fs.displayname, ''), concat('user-', fs.user_id::text)) as displayname,
  fs.reputation,
  fs.location,
  fs.websiteurl,
  fs.total_badges,
  fs.gold_badges,
  fs.silver_badges,
  fs.bronze_badges,
  fs.questions,
  fs.answers,
  fs.accepted_questions,
  fs.closed_questions,
  fs.question_accept_rate_pct,
  fs.question_close_rate_pct,
  fs.avg_answer_score,
  fs.avg_question_views,
  fs.avg_post_score,
  fs.upvotes_cast,
  fs.downvotes_cast,
  fs.vote_polarity,
  fs.favorites_cast,
  fs.bounty_events,
  fs.bounty_amount_total,
  fs.comments_made,
  fs.comment_score,
  fs.avg_comment_len,
  fs.edits_made,
  fs.edited_posts,
  fs.dup_links_out,
  fs.dup_links_in,
  fs.related_links,
  fs.top_tag,
  fs.top_tag_len_bucket,
  fs.prestige_rank,
  fs.score_decile,
  fs.engagement_score,
  fs.is_high_engagement,
  fs.is_high_quality,
  fs.last_seen_any,
  coalesce(fs.duplicate_closes,0) as duplicate_closes_by_user,
  case
    when fs.is_high_engagement = 1 and fs.is_high_quality = 1 then 'elite'
    when fs.is_high_engagement = 1 then 'engaged'
    when fs.is_high_quality = 1 then 'quality'
    else 'regular'
  end as cohort
from final_scored fs
where fs.last_seen_any >= (select date_trunc('month', now()) - interval '90 days')
order by fs.global_rank
limit 200;