-- {"query": "223.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3553} 
with
-- recent active users with reputation tiers
recent_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.location,
    u.creationdate,
    u.lastaccessdate,
    case
      when u.reputation >= 100000 then 'legend'
      when u.reputation >= 20000 then 'elite'
      when u.reputation >= 5000 then 'pro'
      when u.reputation >= 1000 then 'regular'
      else 'newbie'
    end as rep_tier,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as norm_location
  from users u
  where u.lastaccessdate >= (select max(p.creationdate) from posts p where p.posttypeid in (1,2)) - interval '365 days'
),
-- questions and answers with derived metrics
qa as (
  select
    p.id,
    p.posttypeid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.owneruserid,
    p.parentid,
    p.acceptedanswerid,
    p.title,
    p.tags,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.closeddate,
    p.communityowneddate
  from posts p
  where p.posttypeid in (1,2) -- questions and answers
),
-- map answers to their question and compute answer age ranks per question
answers_ranked as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as answer_ownerid,
    a.creationdate as answer_date,
    a.score as answer_score,
    row_number() over (partition by a.parentid order by a.creationdate) as rn_by_time,
    row_number() over (partition by a.parentid order by a.score desc, a.creationdate) as rn_by_score,
    rank() over (partition by a.parentid order by a.score desc) as rnk_score,
    dense_rank() over (partition by a.parentid order by a.creationdate) as dr_time
  from qa a
  where a.posttypeid = 2
),
-- compute per-question aggregates and time-to-first-answer
question_agg as (
  select
    q.id as question_id,
    q.owneruserid as question_ownerid,
    q.creationdate as question_date,
    q.score as question_score,
    q.viewcount,
    q.title,
    q.tags,
    q.answercount,
    q.commentcount,
    q.favoritecount,
    q.closeddate,
    q.communityowneddate,
    min(a.answer_date) as first_answer_date,
    avg(a.answer_score) as avg_answer_score,
    max(a.answer_score) as max_answer_score,
    count(a.answer_id) as actual_answer_count,
    sum(case when a.rn_by_time = 1 then 1 else 0 end) as has_any_answer,
    count(*) filter (where a.rn_by_score = 1) as top_answer_candidates
  from qa q
  left join answers_ranked a
    on a.question_id = q.id
  where q.posttypeid = 1
  group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.title, q.tags, q.answercount, q.commentcount, q.favoritecount, q.closeddate, q.communityowneddate
),
-- time to accepted answer and whether accepted was fastest or highest scored
accepted_answer_eval as (
  select
    q.question_id,
    q.question_ownerid,
    q.question_date,
    q.title,
    q.tags,
    q.viewcount,
    q.question_score,
    q.answercount,
    q.closeddate,
    q.communityowneddate,
    q.first_answer_date,
    extract(epoch from (min(a.answer_date) filter (where a.answer_id = p.acceptedanswerid) - q.question_date)) / 3600.0 as hours_to_accept,
    case when min(a.rn_by_time) filter (where a.answer_id = p.acceptedanswerid) = 1 then 1 else 0 end as accepted_is_fastest,
    case when min(a.rn_by_score) filter (where a.answer_id = p.acceptedanswerid) = 1 then 1 else 0 end as accepted_is_topscored,
    q.avg_answer_score,
    q.max_answer_score,
    q.actual_answer_count,
    q.top_answer_candidates
  from question_agg q
  join posts p on p.id = q.question_id
  left join answers_ranked a on a.question_id = q.question_id
  group by q.question_id, q.question_ownerid, q.question_date, q.title, q.tags, q.viewcount, q.question_score, q.answercount, q.closeddate, q.communityowneddate, q.first_answer_date
),
-- votes summary per post with pivot-like aggregation
votes_summary as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 1 then 1 else 0 end) as accepted_marks,
    sum(case when v.votetypeid = 12 then 1 else 0 end) as spam_flags,
    sum(case when v.votetypeid = 10 then 1 else 0 end) as delete_votes,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
    max(v.creationdate) as last_vote_at
  from votes v
  group by v.postid
),
-- extract close reasons via PostHistory JSON/comment field
close_events as (
  select
    ph.postid,
    min(ph.creationdate) as first_closed_at,
    max(ph.creationdate) as last_closed_at,
    count(*) as close_events,
    string_agg(distinct crt.name, ', ' order by crt.name) as close_reasons
  from posthistory ph
  left join closerreasontypes crt
    on ph.posthistorytypeid = 10
   and crt.id::varchar = nullif(regexp_replace(coalesce(ph.comment,''), '[^0-9]', '', 'g'), '')
  where ph.posthistorytypeid = 10
  group by ph.postid
),
-- tag expansion for questions
question_tags as (
  select
    q.question_id,
    unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
  from accepted_answer_eval q
  where q.tags is not null and length(q.tags) > 2
),
-- popular tag filter
popular_tags as (
  select t.tagname
  from tags t
  where t.count >= (select percentile_disc(0.9) within group (order by count) from tags)
),
-- users with badges and first badge date
user_badges as (
  select
    b.userid,
    min(b.date) as first_badge_date,
    count(*) as badge_count,
    sum(case when b.class = 1 then 1 else 0 end) as golds,
    sum(case when b.class = 2 then 1 else 0 end) as silvers,
    sum(case when b.class = 3 then 1 else 0 end) as bronzes
  from badges b
  group by b.userid
),
-- cross post links identifying duplicates and linked posts
post_links_expand as (
  select
    pl.postid,
    pl.relatedpostid,
    lt.name as link_type,
    pl.creationdate as link_date
  from postlinks pl
  join linktypes lt on lt.id = pl.linktypeid
),
-- correlated subquery to get author's average answer score on same tag
author_tag_perf as (
  select
    q.question_id,
    (
      select avg(a2.answer_score::numeric)
      from answers_ranked a2
      join posts q2 on q2.id = a2.question_id and q2.posttypeid = 1
      where a2.answer_ownerid = q.question_ownerid
        and exists (
          select 1
          from question_tags qt2
          where qt2.question_id = q2.id
            and qt2.tagname in (select tagname from question_tags qt where qt.question_id = q.question_id)
        )
    ) as author_avg_answer_score_in_tags
  from accepted_answer_eval q
),
-- windowed activity metrics per user
user_activity as (
  select
    u.id as userid,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    count(*) as total_posts,
    max(p.creationdate) as last_post_at,
    sum(coalesce(vs.upvotes,0) - coalesce(vs.downvotes,0)) as net_votes,
    percent_rank() over (order by count(*) desc) as activity_percentile
  from users u
  left join posts p on p.owneruserid = u.id
  left join votes_summary vs on vs.postid = p.id
  group by u.id
),
-- choose a time frame and compute rolling weekly question volumes
weekly_question_volume as (
  select
    date_trunc('week', q.question_date) as week_start,
    count(*) as questions,
    sum(q.answercount) as answers_reported,
    count(*) filter (where q.first_answer_date is not null) as with_answers
  from accepted_answer_eval q
  group by date_trunc('week', q.question_date)
),
weekly_q_with_windows as (
  select
    w.*,
    sum(questions) over (order by week_start rows between 3 preceding and current row) as questions_4wk,
    avg(questions::numeric) over (order by week_start rows between 7 preceding and current row) as questions_8wk_avg,
    lag(questions) over (order by week_start) as prev_week_questions
  from weekly_question_volume w
),
-- synthesize a per-question difficulty heuristic
question_difficulty as (
  select
    q.question_id,
    case
      when q.answercount = 0 or q.first_answer_date is null then 'unanswered'
      when q.hours_to_accept is null then 'no-accept'
      when q.hours_to_accept <= 1 then 'instant'
      when q.hours_to_accept <= 24 then 'day'
      when q.hours_to_accept <= 168 then 'week'
      else 'long-tail'
    end as accept_latency_bucket,
    case
      when q.viewcount is null then 'unknown'
      when q.viewcount >= 100000 then 'viral'
      when q.viewcount >= 10000 then 'popular'
      when q.viewcount >= 1000 then 'normal'
      else 'low'
    end as view_bucket,
    (coalesce(q.question_score,0) + coalesce(q.avg_answer_score,0)) as composite_score,
    (coalesce(q.top_answer_candidates,0) >= 1 and coalesce(q.actual_answer_count,0) >= 1) as competitive_answers
  from accepted_answer_eval q
),
-- combine everything
final as (
  select
    q.question_id,
    q.title,
    q.tags,
    q.question_date,
    q.viewcount,
    q.question_score,
    q.answercount,
    q.first_answer_date,
    q.hours_to_accept,
    q.accepted_is_fastest,
    q.accepted_is_topscored,
    dv.accept_latency_bucket,
    dv.view_bucket,
    dv.composite_score,
    dv.competitive_answers,
    vs.upvotes,
    vs.downvotes,
    vs.bounty_awarded,
    vs.last_vote_at,
    ce.first_closed_at,
    ce.last_closed_at,
    ce.close_events,
    ce.close_reasons,
    ru.displayname as asker,
    ru.rep_tier as asker_tier,
    ru.norm_location as asker_location,
    ub.badge_count as asker_badges,
    ua.total_posts as asker_total_posts,
    ua.net_votes as asker_net_votes,
    atp.author_avg_answer_score_in_tags,
    -- tag info
    string_agg(distinct case when qt.tagname in (select tagname from popular_tags) then qt.tagname else null end, ', ') filter (where qt.tagname in (select tagname from popular_tags)) as popular_tags,
    count(distinct case when pl.link_type = 'Duplicate' then pl.relatedpostid end) as duplicate_of_count,
    count(distinct case when pl.link_type = 'Linked' then pl.relatedpostid end) as linked_count,
    -- synthetic quality signal
    (
      coalesce(vs.upvotes,0)
      - coalesce(vs.downvotes,0)
      + case when q.accepted_is_topscored = 1 then 2 else 0 end
      + case when q.accepted_is_fastest = 1 then 1 else 0 end
      + case when dv.view_bucket in ('popular','viral') then 2 else 0 end
      - least(coalesce(ce.close_events,0), 3)
    ) as quality_signal,
    -- normalize title to lower, strip punctuation, and length metrics
    length(coalesce(q.title,'')) as title_len,
    length(regexp_replace(coalesce(q.title,''), '[^a-zA-Z0-9 ]', '', 'g')) as title_alnum_len,
    regexp_replace(lower(coalesce(q.title,'')), '\s+', ' ', 'g') as norm_title
  from accepted_answer_eval q
  left join votes_summary vs on vs.postid = q.question_id
  left join close_events ce on ce.postid = q.question_id
  left join recent_users ru on ru.id = q.question_ownerid
  left join user_badges ub on ub.userid = q.question_ownerid
  left join user_activity ua on ua.userid = q.question_ownerid
  left join author_tag_perf atp on atp.question_id = q.question_id
  left join question_tags qt on qt.question_id = q.question_id
  left join post_links_expand pl on pl.postid = q.question_id
  left join question_difficulty dv on dv.question_id = q.question_id
  group by
    q.question_id, q.title, q.tags, q.question_date, q.viewcount, q.question_score, q.answercount, q.first_answer_date, q.hours_to_accept, q.accepted_is_fastest, q.accepted_is_topscored,
    vs.upvotes, vs.downvotes, vs.bounty_awarded, vs.last_vote_at,
    ce.first_closed_at, ce.last_closed_at, ce.close_events, ce.close_reasons,
    ru.displayname, ru.rep_tier, ru.norm_location,
    ub.badge_count, ua.total_posts, ua.net_votes,
    atp.author_avg_answer_score_in_tags,
    dv.accept_latency_bucket, dv.view_bucket, dv.composite_score, dv.competitive_answers
),
ranked as (
  select
    f.*,
    row_number() over (order by quality_signal desc nulls last, viewcount desc nulls last, question_date desc) as rn,
    percentile_cont(0.5) within group (order by coalesce(hours_to_accept, 1e9)) over () as median_hours_to_accept,
    avg(viewcount::numeric) over () as avg_views_all,
    stddev_samp(coalesce(viewcount,0)::numeric) over () as std_views_all
  from final f
)
select
  r.question_id,
  r.asker,
  r.asker_tier,
  r.asker_location,
  r.asker_badges,
  r.question_date,
  r.title,
  r.norm_title,
  r.tags,
  r.popular_tags,
  r.viewcount,
  r.upvotes,
  r.downvotes,
  r.bounty_awarded,
  r.hours_to_accept,
  r.accepted_is_fastest,
  r.accepted_is_topscored,
  r.close_events,
  r.close_reasons,
  r.duplicate_of_count,
  r.linked_count,
  r.quality_signal,
  r.median_hours_to_accept,
  r.avg_views_all,
  r.std_views_all,
  r.rn as rank_overall
from ranked r
where (
    r.viewcount is not null
    and (r.viewcount > r.avg_views_all + 2 * coalesce(r.std_views_all, 0))
  )
  or (
    r.hours_to_accept is not null
    and r.hours_to_accept > r.median_hours_to_accept * 4
  )
order by r.rn
limit 200;