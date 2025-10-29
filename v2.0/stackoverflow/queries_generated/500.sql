-- {"query": "500.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2849} 
with recent_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    u.upvotes,
    u.downvotes,
    row_number() over (order by u.creationdate desc, u.id) as rn
  from users u
),
user_activity as (
  select
    u.id as user_id,
    count(distinct p.id) as post_count,
    count(distinct c.id) as comment_count,
    sum(coalesce(p.score,0)) as post_score_sum,
    sum(case when p.posttypeid = 1 then coalesce(p.viewcount,0) else 0 end) as question_views_sum,
    max(greatest(coalesce(p.lastactivitydate, timestamp 'epoch'), coalesce(c.creationdate, timestamp 'epoch'))) as last_activity
  from users u
  left join posts p on p.owneruserid = u.id
  left join comments c on c.userid = u.id
  group by u.id
),
user_badges as (
  select
    b.userid as user_id,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    count(*) filter (where b.tagbased = 1) as tag_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
question_metrics as (
  select
    u.id as user_id,
    count(*) filter (where p.posttypeid = 1) as questions,
    count(*) filter (where p.posttypeid = 1 and p.acceptedanswerid is not null) as accepted_questions,
    avg(nullif(p.answercount,0)) filter (where p.posttypeid = 1) as avg_answers_per_question,
    percentile_cont(0.5) within group (order by coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as p50_views,
    sum(case when p.posttypeid = 1 and p.closeddate is not null then 1 else 0 end) as closed_questions
  from users u
  left join posts p on p.owneruserid = u.id and p.posttypeid = 1
  group by u.id
),
answer_metrics as (
  select
    u.id as user_id,
    count(*) filter (where p.posttypeid = 2) as answers,
    count(*) filter (
      where p.posttypeid = 2
        and exists (
          select 1
          from posts q
          where q.id = p.parentid
            and q.acceptedanswerid = p.id
        )
    ) as accepted_answers,
    avg(coalesce(p.score,0)) filter (where p.posttypeid = 2) as avg_answer_score
  from users u
  left join posts p on p.owneruserid = u.id and p.posttypeid = 2
  group by u.id
),
post_link_stats as (
  select
    p.owneruserid as user_id,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links,
    count(*) filter (where pl.linktypeid = 1) as normal_links
  from postlinks pl
  join posts p on p.id = pl.postid
  group by p.owneruserid
),
vote_agg as (
  select
    p.owneruserid as user_id,
    count(*) filter (where v.votetypeid = 2) as upmods,
    count(*) filter (where v.votetypeid = 3) as downmods,
    count(*) filter (where v.votetypeid = 5) as favorites,
    sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total
  from votes v
  join posts p on p.id = v.postid
  group by p.owneruserid
),
tag_usage as (
  select
    p.owneruserid as user_id,
    lower(trim(both '<>' from unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')))) as tagname,
    count(*) as tag_count,
    sum(coalesce(p.score,0)) as tag_score_sum
  from posts p
  where p.posttypeid = 1
    and p.tags is not null
    and length(p.tags) > 2
  group by p.owneruserid, lower(trim(both '<>' from unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><'))))
),
top_tags as (
  select
    t.user_id,
    string_agg(tt.tagname || ':' || tt.tag_count, ', ' order by tt.tag_count desc, tt.tagname asc) as top3_tags
  from (
    select
      tu.user_id,
      tu.tagname,
      tu.tag_count,
      row_number() over (partition by tu.user_id order by tu.tag_count desc, tu.tagname) as rk
    from tag_usage tu
  ) tt
  where tt.rk <= 3
  group by tT.user_id
),
edits_and_closures as (
  select
    ph.userid as user_id,
    count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edits_made,
    count(*) filter (where ph.posthistorytypeid in (10,11)) as close_reopen_votes,
    count(*) filter (where ph.posthistorytypeid = 19) as protections
  from posthistory ph
  group by ph.userid
),
question_close_reasons as (
  select
    q.owneruserid as user_id,
    crt.name as close_reason_name,
    count(*) as close_count
  from posts q
  join posthistory ph on ph.postid = q.id and ph.posthistorytypeid = 10
  left join closereasontypes crt
    on (case
          when ph.comment ~ '^[0-9]+$' then cast(ph.comment as integer)
          else null
        end) = crt.id
  group by q.owneruserid, crt.name
),
close_reason_pivot as (
  select
    user_id,
    sum(close_count) filter (where close_reason_name = 'Duplicate') as closed_duplicate,
    sum(close_count) filter (where close_reason_name = 'Off-topic') as closed_offtopic,
    sum(close_count) filter (where close_reason_name = 'Needs details or clarity') as closed_needs_details,
    sum(close_count) filter (where close_reason_name = 'Needs more focus') as closed_needs_focus,
    sum(close_count) filter (where close_reason_name = 'Opinion-based') as closed_opinion
  from question_close_reasons
  group by user_id
),
ranked_users as (
  select
    ru.id as user_id,
    ru.displayname,
    ru.reputation,
    ua.post_count,
    ua.comment_count,
    ua.post_score_sum,
    ua.question_views_sum,
    coalesce(ua.last_activity, ru.creationdate) as last_activity,
    ub.gold_badges,
    ub.silver_badges,
    ub.bronze_badges,
    ub.tag_badges,
    qm.questions,
    qm.accepted_questions,
    qm.avg_answers_per_question,
    am.answers,
    am.accepted_answers,
    am.avg_answer_score,
    pls.duplicate_links,
    pls.normal_links,
    va.upmods,
    va.downmods,
    va.favorites,
    va.bounty_total,
    tt.top3_tags,
    eac.edits_made,
    eac.close_reopen_votes,
    eac.protections,
    crp.closed_duplicate,
    crp.closed_offtopic,
    crp.closed_needs_details,
    crp.closed_needs_focus,
    crp.closed_opinion,
    row_number() over (
      order by
        coalesce(va.upmods,0) - coalesce(va.downmods,0) + coalesce(ua.post_score_sum,0) desc,
        coalesce(am.accepted_answers,0) desc,
        coalesce(qm.accepted_questions,0) desc,
        ru.reputation desc,
        ru.id
    ) as activity_rank
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.id
  left join user_badges ub on ub.user_id = ru.id
  left join question_metrics qm on qm.user_id = ru.id
  left join answer_metrics am on am.user_id = ru.id
  left join post_link_stats pls on pls.user_id = ru.id
  left join vote_agg va on va.user_id = ru.id
  left join top_tags tt on tt.user_id = ru.id
  left join edits_and_closures eac on eac.user_id = ru.id
  left join close_reason_pivot crp on crp.user_id = ru.id
),
thresholds as (
  select
    avg(nullif(post_count,0)) as avg_posts,
    avg(nullif(comment_count,0)) as avg_comments,
    percentile_cont(0.9) within group (order by coalesce(reputation,0)) as p90_rep,
    percentile_cont(0.9) within group (order by coalesce(post_score_sum,0)) as p90_score
  from ranked_users
),
flagged_users as (
  select
    r.*,
    case
      when coalesce(r.downmods,0) > coalesce(r.upmods,0) and coalesce(r.post_score_sum,0) < 0 then 1
      when coalesce(r.closed_duplicate,0) + coalesce(r.closed_offtopic,0) >= 10 then 1
      when coalesce(r.answers,0) = 0 and coalesce(r.questions,0) >= 20 and coalesce(r.accepted_questions,0) = 0 then 1
      else 0
    end as risk_flag
  from ranked_users r
)
select
  r.user_id,
  coalesce(nullif(trim(r.displayname), ''), '(anonymous)') as displayname,
  r.reputation,
  r.activity_rank,
  r.post_count,
  r.comment_count,
  r.post_score_sum,
  r.question_views_sum,
  r.questions,
  r.accepted_questions,
  r.answers,
  r.accepted_answers,
  round(coalesce(r.avg_answer_score,0)::numeric, 2) as avg_answer_score,
  round(coalesce(r.avg_answers_per_question,0)::numeric, 2) as avg_ans_per_question,
  coalesce(r.gold_badges,0) as gold_badges,
  coalesce(r.silver_badges,0) as silver_badges,
  coalesce(r.bronze_badges,0) as bronze_badges,
  coalesce(r.tag_badges,0) as tag_badges,
  coalesce(r.upmods,0) as upvotes_received,
  coalesce(r.downmods,0) as downvotes_received,
  coalesce(r.favorites,0) as favorites_received,
  coalesce(r.bounty_total,0) as bounty_total,
  coalesce(r.duplicate_links,0) as duplicate_links,
  coalesce(r.normal_links,0) as normal_links,
  coalesce(r.closed_duplicate,0) as closed_duplicate,
  coalesce(r.closed_offtopic,0) as closed_offtopic,
  coalesce(r.closed_needs_details,0) as closed_needs_details,
  coalesce(r.closed_needs_focus,0) as closed_needs_focus,
  coalesce(r.closed_opinion,0) as closed_opinion,
  coalesce(r.edits_made,0) as edits_made,
  coalesce(r.close_reopen_votes,0) as close_reopen_votes,
  coalesce(r.protections,0) as protections,
  coalesce(r.top3_tags, '(none)') as top3_tags,
  r.last_activity,
  case
    when r.reputation >= t.p90_rep and r.post_score_sum >= t.p90_score then 'elite'
    when r.reputation >= t.p90_rep then 'high-rep'
    when r.post_score_sum >= t.p90_score then 'high-score'
    else 'standard'
  end as tier,
  fu.risk_flag,
  case
    when coalesce(r.post_count,0) = 0 then null
    else round((coalesce(r.upmods,0)::numeric - coalesce(r.downmods,0)::numeric) / nullif(r.post_count,0), 3)
  end as net_votes_per_post,
  case
    when r.comment_count is null or r.post_count is null then null
    else round((r.comment_count::numeric / nullif(r.post_count,0)), 3)
  end as comments_per_post
from ranked_users r
cross join thresholds t
left join flagged_users fu on fu.user_id = r.user_id
where
  (
    r.reputation >= t.p90_rep
    or r.post_score_sum >= t.p90_score
    or fu.risk_flag = 1
    or r.activity_rank <= 100
  )
order by
  r.activity_rank,
  r.user_id
limit 500;