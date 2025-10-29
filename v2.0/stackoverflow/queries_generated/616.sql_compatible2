with
recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
    count(distinct b.id) as badge_count,
    sum(case b.class when 1 then 3 when 2 then 2 when 3 then 1 else 0 end) as badge_weight,
    max(b.date) as last_badge_date,
    row_number() over (order by u.reputation desc, u.id) as rn
  from users u
  left join badges b
    on b.userid = u.id
    and b.date >= u.creationdate
  where u.creationdate >= (select max(creationdate) - interval '3 years' from users)
  group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.websiteurl
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
    case when p.tags is not null and length(p.tags) >= 2
         then string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
         else cast(array[] as varchar[]) end as tag_arr
  from posts p
  where p.posttypeid = 1
),
user_post_stats as (
  select
    qp.user_id,
    count(*) as q_count,
    sum(qp.score) as q_score_sum,
    avg(qp.score) as q_score_avg,
    percentile_disc(0.9) within group (order by qp.score) as q_score_p90,
    min(qp.creationdate) as first_q_date,
    max(qp.creationdate) as last_q_date,
    sum(case when qp.closeddate is not null then 1 else 0 end) as q_closed_count,
    sum(qp.viewcount) as q_views_sum,
    max(qp.viewcount) as q_views_max
  from question_posts qp
  group by qp.user_id
),
user_top_tags as (
  select
    qp.user_id,
    lower(cast(t as varchar)) as tag,
    count(*) as tag_freq,
    row_number() over (partition by qp.user_id order by count(*) desc, lower(cast(t as varchar))) as tag_rank
  from question_posts qp,
       lateral unnest(qp.tag_arr) as t
  group by qp.user_id, lower(cast(t as varchar))
),
answers_enriched as (
  select
    p.id as answer_id,
    p.parentid as question_id,
    p.owneruserid as user_id,
    p.creationdate,
    p.score,
    row_number() over (partition by p.owneruserid order by p.score desc, p.creationdate) as rn_by_score,
    exists (
      select 1
      from posts q
      where q.id = p.parentid and q.acceptedanswerid = p.id
    ) as is_accepted
  from posts p
  where p.posttypeid = 2
),
best_answers as (
  select user_id,
         max(score) as best_answer_score,
         sum(case when is_accepted then 1 else 0 end) as accepted_count,
         count(*) as total_answers,
         min(case when rn_by_score = 1 then creationdate end) as best_answer_date
  from answers_enriched
  group by user_id
),
engagement as (
  select
    u.id as user_id,
    coalesce(sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end), 0) as net_votes_cast_on_posts,
    coalesce(sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end), 0) as bounty_started,
    coalesce(sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end), 0) as bounty_awarded,
    count(distinct c.id) filter (where c.userid = u.id) as comments_made
  from users u
  left join votes v on v.userid = u.id
  left join comments c on c.userid = u.id
  group by u.id
),
link_behavior as (
  select
    p.owneruserid as user_id,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_links_out,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as related_links_out,
    sum(case when pl.linktypeid = 3 then 0 else 1 end) as non_dup_links_out
  from postlinks pl
  join posts p on p.id = pl.postid
  group by p.owneruserid
),
post_history_agg as (
  select
    p.owneruserid as user_id,
    sum(case when ph.posthistorytypeid = 10 then 1 else 0 end) as close_events,
    sum(case when ph.posthistorytypeid = 19 then 1 else 0 end) as protect_events,
    sum(case when ph.posthistorytypeid = 24 then 1 else 0 end) as suggested_edits_applied
  from posthistory ph
  join posts p on p.id = ph.postid
  group by p.owneruserid
),
users_with_no_posts as (
  select u.id as user_id
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
  having count(p.id) = 0
),
active_segment as (
  select ru.user_id
  from recent_users ru
  where ru.rn <= 1000
),
nonpost_segment as (
  select user_id
  from users_with_no_posts
),
target_users as (
  select user_id from active_segment
  union
  select user_id from nonpost_segment
),
assembled as (
  select
    tu.user_id,
    ru.displayname,
    ru.reputation,
    ru.creationdate as user_since,
    coalesce(nullif(ru.location, ''), 'Unknown') as location,
    ru.websiteurl,
    ru.badge_count,
    ru.badge_weight,
    ru.last_badge_date,
    ups.q_count,
    ups.q_score_sum,
    ups.q_score_avg,
    ups.q_score_p90,
    ups.first_q_date,
    ups.last_q_date,
    ups.q_closed_count,
    ups.q_views_sum,
    ups.q_views_max,
    ba.best_answer_score,
    ba.accepted_count,
    ba.total_answers,
    ba.best_answer_date,
    e.net_votes_cast_on_posts,
    e.bounty_started,
    e.bounty_awarded,
    e.comments_made,
    lb.duplicate_links_out,
    lb.related_links_out,
    lb.non_dup_links_out,
    pha.close_events,
    pha.protect_events,
    pha.suggested_edits_applied,
    string_agg(ut.tag || ':' || cast(ut.tag_freq as varchar), ', ' order by ut.tag_rank) filter (where ut.tag_rank <= 5) as top5_tags_with_freq,
    case
      when ups.q_count is null then 'NoPosts'
      when coalesce(ba.total_answers,0) = 0 and ups.q_count > 0 then 'OnlyQuestions'
      when coalesce(ups.q_count,0) = 0 and coalesce(ba.total_answers,0) > 0 then 'OnlyAnswers'
      else 'Mixed'
    end as posting_profile,
    case
      when ru.reputation >= 100000 then 'Legendary'
      when ru.reputation >= 10000 then 'HighRep'
      when ru.reputation >= 1000 then 'Established'
      else 'Rookie'
    end as rep_bucket,
    round(coalesce(cast(ups.q_views_sum as numeric) / nullif(ups.q_count,0), 0), 2) as avg_views_per_q,
    round(coalesce(cast(ba.accepted_count as numeric) / nullif(ba.total_answers,0), 0), 4) as acceptance_rate,
    (coalesce(ru.badge_weight,0) + coalesce(ups.q_score_sum,0) + 2 * coalesce(ba.best_answer_score,0)) as composite_score
  from target_users tu
  left join recent_users ru on ru.user_id = tu.user_id
  left join user_post_stats ups on ups.user_id = tu.user_id
  left join best_answers ba on ba.user_id = tu.user_id
  left join engagement e on e.user_id = tu.user_id
  left join link_behavior lb on lb.user_id = tu.user_id
  left join post_history_agg pha on pha.user_id = tu.user_id
  left join lateral (
    select tag, tag_freq, tag_rank
    from user_top_tags utt
    where utt.user_id = tu.user_id and utt.tag_rank <= 5
    order by tag_rank
  ) ut on true
  group by
    tu.user_id, ru.displayname, ru.reputation, ru.creationdate, ru.location, ru.websiteurl,
    ru.badge_count, ru.badge_weight, ru.last_badge_date,
    ups.q_count, ups.q_score_sum, ups.q_score_avg, ups.q_score_p90, ups.first_q_date, ups.last_q_date,
    ups.q_closed_count, ups.q_views_sum, ups.q_views_max,
    ba.best_answer_score, ba.accepted_count, ba.total_answers, ba.best_answer_date,
    e.net_votes_cast_on_posts, e.bounty_started, e.bounty_awarded, e.comments_made,
    lb.duplicate_links_out, lb.related_links_out, lb.non_dup_links_out,
    pha.close_events, pha.protect_events, pha.suggested_edits_applied, tu.user_id
),
ranked as (
  select
    a.*,
    dense_rank() over (order by composite_score desc nulls last, coalesce(q_count,0) desc, coalesce(total_answers,0) desc) as overall_rank,
    row_number() over (partition by rep_bucket order by composite_score desc nulls last) as bucket_rank
  from assembled a
)
select *
from ranked
where (overall_rank <= 500 or bucket_rank <= 50)
order by overall_rank, user_id;