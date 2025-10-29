with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
    count(case when b.class = 1 then 1 end) as gold_badges,
    count(case when b.class = 2 then 1 end) as silver_badges,
    count(case when b.class = 3 then 1 end) as bronze_badges,
    max(b.date) as last_badge_date
  from users u
  left join badges b
    on b.userid = u.id
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
  group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.websiteurl
),
question_activity as (
  select
    p.owneruserid as user_id,
    p.id as question_id,
    p.creationdate as question_date,
    p.score as question_score,
    p.viewcount,
    p.favoritecount,
    p.answercount,
    p.tags,
    p.title,
    p.closeddate,
    date_trunc('month', p.creationdate) as question_month,
    count(a.id) as answers_total,
    sum(case when a.score > 0 then 1 else 0 end) as answers_positive,
    max(a.score) as best_answer_score
  from posts p
  left join posts a
    on a.parentid = p.id
    and a.posttypeid = 2
  where p.posttypeid = 1
  group by p.owneruserid, p.id, p.creationdate, p.score, p.viewcount, p.favoritecount, p.answercount, p.tags, p.title, p.closeddate, date_trunc('month', p.creationdate)
),
comment_stats as (
  select
    c.userid as user_id,
    count(*) as comments_count,
    avg(nullif(c.score,0)) as avg_nonzero_comment_score,
    max(c.creationdate) as last_comment_date,
    count(case when lower(c.text) like '%thanks%' or lower(c.text) like '%thank%' then 1 end) as thanky_comments
  from comments c
  group by c.userid
),
vote_agg as (
  select
    p.owneruserid as user_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_received,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_received,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_received,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_flow
  from posts p
  left join votes v
    on v.postid = p.id
  group by p.owneruserid
),
dup_network as (
  select
    p.owneruserid as user_id,
    count(case when pl.linktypeid = 3 then 1 end) as dup_links_out,
    count(case when pl.linktypeid = 3 and pl.relatedpostid = p.acceptedanswerid then 1 end) as dup_links_weird_case
  from posts p
  left join postlinks pl
    on pl.postid = p.id
  group by p.owneruserid
),
post_edits as (
  select
    ph.postid,
    ph.userid as editor_user_id,
    count(*) as edit_count,
    min(ph.creationdate) as first_edit_at,
    max(ph.creationdate) as last_edit_at,
    count(case when ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35) then 1 end) as mod_like_actions
  from posthistory ph
  where ph.posthistorytypeid in (4,5,6,7,8,9,10,11,12,13,14,15,19,20,24,31,33,34,35,36,37,38,50,52,53,66)
  group by ph.postid, ph.userid
),
tag_unpivot as (
  select
    p.id as post_id,
    p.owneruserid as user_id,
    lower(trim(t)) as tag
  from posts p,
    lateral (
      select unnest(string_to_array(substring(p.tags from 2 for greatest(char_length(p.tags)-2,0)), '><')) as t
    ) as uu
  where p.posttypeid = 1
),
user_tag_rank as (
  select
    tu.user_id,
    tu.tag,
    count(*) as tag_q_count,
    sum(q.score) as tag_q_score,
    row_number() over (partition by tu.user_id order by count(*) desc, sum(q.score) desc, min(q.creationdate)) as rn_tag
  from tag_unpivot tu
  join posts q on q.id = tu.post_id
  group by tu.user_id, tu.tag
),
monthly_perf as (
  select
    qa.user_id,
    qa.question_month,
    count(*) as questions_in_month,
    avg(qa.question_score) as avg_q_score,
    percentile_cont(0.5) within group (order by coalesce(qa.viewcount,0)) as med_views,
    sum(case when qa.closeddate is not null then 1 else 0 end) as closed_count
  from question_activity qa
  group by qa.user_id, qa.question_month
),
user_windows as (
  select
    ru.user_id,
    sum(mp.questions_in_month) over (partition by ru.user_id order by mp.question_month rows between 5 preceding and current row) as q_6mo_rolling,
    avg(mp.avg_q_score) over (partition by ru.user_id order by mp.question_month rows between 5 preceding and current row) as avg_q_score_6mo,
    sum(mp.closed_count) over (partition by ru.user_id order by mp.question_month rows between 5 preceding and current row) as closed_6mo
  from recent_users ru
  left join monthly_perf mp
    on mp.user_id = ru.user_id
  group by ru.user_id, mp.question_month, mp.questions_in_month, mp.avg_q_score, mp.closed_count
),
top_q_per_user as (
  select
    qa.user_id,
    qa.question_id,
    qa.title,
    qa.question_score,
    qa.viewcount,
    qa.best_answer_score
  from (
    select
      qa.*,
      row_number() over (partition by qa.user_id order by qa.question_score desc nulls last, qa.viewcount desc nulls last) as rn
    from question_activity qa
  ) qa
  where qa.rn = 1
),
moderation_flags as (
  select
    p.owneruserid as user_id,
    count(case when ph.posthistorytypeid in (10,35) then 1 end) as closed_or_migrated,
    count(case when ph.posthistorytypeid in (11) then 1 end) as reopened
  from posts p
  left join posthistory ph on ph.postid = p.id
  group by p.owneruserid
),
null_logic_demo as (
  select
    ru.user_id,
    case
      when coalesce(ru.location, '') = '' then null
      when lower(ru.location) like '%remote%' then 'Remote'
      else split_part(replace(replace(ru.location, ',', ','), ';', ','), ',', 1)
    end as normalized_location
  from recent_users ru
),
final_scores as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.creationdate,
    nl.normalized_location,
    ru.websiteurl,
    ru.gold_badges, ru.silver_badges, ru.bronze_badges,
    coalesce(va.upvotes_received,0) - coalesce(va.downvotes_received,0) as net_votes_received,
    coalesce(va.favorites_received,0) as favorites_received,
    coalesce(va.bounty_flow,0) as bounty_flow,
    coalesce(cs.comments_count,0) as comments_count,
    coalesce(cs.avg_nonzero_comment_score,0) as avg_nonzero_comment_score,
    coalesce(cs.thanky_comments,0) as thanky_comments,
    coalesce(dn.dup_links_out,0) as dup_links_out,
    coalesce(mf.closed_or_migrated,0) as closed_or_migrated,
    coalesce(mf.reopened,0) as reopened,
    uw.q_6mo_rolling,
    uw.avg_q_score_6mo,
    uw.closed_6mo,
    tq.question_id as top_question_id,
    tq.title as top_question_title,
    tq.question_score as top_question_score,
    uq.tag as top_tag,
    uq.tag_q_count,
    uq.tag_q_score,
    rank() over (
      order by
        sqrt(greatest(ru.reputation,1)) +
        log(1 + coalesce(va.upvotes_received,0) + coalesce(va.favorites_received,0)) -
        log(1 + coalesce(va.downvotes_received,0)) +
        coalesce(uw.avg_q_score_6mo,0) +
        least(coalesce(tq.question_score,0), 50) / 10.0 +
        coalesce(ru.gold_badges,0) * 2 + coalesce(ru.silver_badges,0) * 1 + coalesce(ru.bronze_badges,0) * 0.25 -
        coalesce(dn.dup_links_out,0) * 0.5 -
        coalesce(mf.closed_or_migrated,0) * 0.25 +
        case when coalesce(cs.avg_nonzero_comment_score,0) > 0.5 then 0.5 else 0 end
      desc
    ) as perf_rank
  from recent_users ru
  left join vote_agg va on va.user_id = ru.user_id
  left join comment_stats cs on cs.user_id = ru.user_id
  left join dup_network dn on dn.user_id = ru.user_id
  left join user_windows uw on uw.user_id = ru.user_id
  left join top_q_per_user tq on tq.user_id = ru.user_id
  left join moderation_flags mf on mf.user_id = ru.user_id
  left join null_logic_demo nl on nl.user_id = ru.user_id
  left join lateral (
    select tag, tag_q_count, tag_q_score
    from user_tag_rank utr
    where utr.user_id = ru.user_id and utr.rn_tag = 1
    fetch first 1 row only
  ) uq on true
)
select
  fs.user_id,
  fs.displayname,
  fs.reputation,
  cast(fs.creationdate as date) as joined,
  coalesce(fs.normalized_location, 'Unknown') as location,
  fs.websiteurl,
  fs.gold_badges || '/' || fs.silver_badges || '/' || fs.bronze_badges as badge_mix,
  fs.net_votes_received,
  fs.favorites_received,
  fs.bounty_flow,
  fs.comments_count,
  round(cast(fs.avg_nonzero_comment_score as numeric), 3) as avg_nonzero_comment_score,
  fs.thanky_comments,
  coalesce(fs.q_6mo_rolling,0) as q_6mo_rolling,
  round(cast(coalesce(fs.avg_q_score_6mo,0) as numeric),2) as avg_q_score_6mo,
  coalesce(fs.closed_6mo,0) as closed_6mo,
  fs.dup_links_out,
  fs.closed_or_migrated,
  fs.reopened,
  fs.top_question_id,
  substring(coalesce(fs.top_question_title,'' ) from 1 for 120) as top_question_title,
  fs.top_question_score,
  coalesce(fs.top_tag,'') as top_tag,
  fs.tag_q_count,
  fs.tag_q_score,
  fs.perf_rank,
  case
    when fs.reputation >= 20000 and coalesce(fs.gold_badges,0) >= 3 then 'elite'
    when fs.reputation >= 10000 then 'expert'
    when fs.reputation >= 3000 then 'advanced'
    when fs.reputation >= 1000 then 'intermediate'
    else 'novice'
  end as tier
from final_scores fs
where
  (fs.top_question_score is null or fs.top_question_score >= 0)
  and (fs.net_votes_received - coalesce(fs.dup_links_out,0) >= -50)
  and (fs.tag_q_count is null or fs.tag_q_count >= 1)
order by fs.perf_rank asc, fs.user_id
limit 250;