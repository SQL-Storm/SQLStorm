-- {"query": "357.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3774} 
with
-- recent active users with profile heuristics
recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.location,
    u.creationdate,
    u.lastaccessdate,
    u.websiteurl,
    u.upvotes,
    u.downvotes,
    u.views,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as norm_location,
    case when u.websiteurl ~* 'https?://'
         then lower(split_part(regexp_replace(u.websiteurl, '^https?://(www\.)?', '', 'i'), '/', 1))
         else null end as website_host
  from users u
  where u.lastaccessdate >= now() - interval '365 days'
),
-- posts in the last 2 years with normalized title/tags
recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.score,
    p.viewcount,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.creationdate,
    p.lastactivitydate,
    p.closeddate,
    p.title,
    p.tags,
    coalesce(p.contentlicense, 'unknown') as contentlicense,
    lower(coalesce(p.title, '')) as title_lc,
    string_to_array(coalesce(substring(p.tags, 2, length(p.tags)-2), ''), '><') as tag_array
  from posts p
  where p.creationdate >= now() - interval '730 days'
),
-- engagement metrics per user/post type using window functions
user_post_metrics as (
  select
    rp.owneruserid as user_id,
    rp.posttypeid,
    count(*) as post_cnt,
    sum(coalesce(rp.viewcount,0)) as total_views,
    sum(coalesce(rp.score,0)) as total_score,
    avg(coalesce(rp.score,0)) as avg_score,
    percentile_cont(0.9) within group (order by coalesce(rp.score,0)) as p90_score,
    max(rp.creationdate) as last_post_date
  from recent_posts rp
  where rp.owneruserid is not null
  group by rp.owneruserid, rp.posttypeid
),
-- votes in last 2 years
recent_votes as (
  select v.postid, v.userid, v.votetypeid, v.creationdate, v.bountyamount
  from votes v
  where v.creationdate >= now() - interval '730 days'
),
-- aggregate votes per post and user
vote_agg as (
  select
    rv.postid,
    rv.userid,
    sum(case when rv.votetypeid = 2 then 1 else 0 end) as up_cnt,
    sum(case when rv.votetypeid = 3 then 1 else 0 end) as down_cnt,
    sum(case when rv.votetypeid = 8 then coalesce(rv.bountyamount,0) else 0 end) as bounty_start,
    sum(case when rv.votetypeid = 9 then coalesce(rv.bountyamount,0) else 0 end) as bounty_close,
    count(*) as total_votes
  from recent_votes rv
  group by rv.postid, rv.userid
),
-- comments sentiment proxy via simple scoring and window ranks
comment_scores as (
  select
    c.postid,
    c.userid,
    sum(c.score) as comment_score,
    count(*) as comment_count,
    max(c.creationdate) as last_comment_date,
    row_number() over (partition by c.postid order by sum(c.score) desc nulls last, count(*) desc, max(c.creationdate) desc) as rn_on_post
  from comments c
  where c.creationdate >= now() - interval '730 days'
  group by c.postid, c.userid
),
-- tag popularity rank
tag_rank as (
  select
    t.tagname,
    t.count,
    dense_rank() over (order by t.count desc nulls last) as popularity_rank
  from tags t
),
-- identify duplicates and link graph degree
post_link_stats as (
  select
    pl.postid,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as dup_links,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as related_links,
    count(*) as all_links,
    count(distinct pl.relatedpostid) as distinct_related
  from postlinks pl
  where pl.creationdate >= now() - interval '730 days'
  group by pl.postid
),
-- closure reasons from PostHistory with JSON details
closure_events as (
  select
    ph.postid,
    min(ph.creationdate) as first_closed_at,
    max(ph.creationdate) as last_closed_at,
    count(*) filter (where ph.posthistorytypeid = 10) as close_events,
    count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
    -- Comment contains CloseReasonId for type 10
    max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_id_raw,
    max(case when ph.posthistorytypeid = 10 then ph.text end) as last_close_json
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
    and ph.creationdate >= now() - interval '730 days'
  group by ph.postid
),
-- map close reason id to name (safe cast to int when numeric)
closure_reason_map as (
  select
    ce.postid,
    ce.first_closed_at,
    ce.last_closed_at,
    ce.close_events,
    ce.reopen_events,
    case
      when ce.last_close_reason_id_raw ~ '^[0-9]+$'
      then crt.name
      else null
    end as last_close_reason_name,
    ce.last_close_json
  from closure_events ce
  left join closerreasontypes crt
    on crt.id = cast(ce.last_close_reason_id_raw as int)
),
-- extract top tags per user (correlated subquery via unnest)
user_top_tags as (
  select
    rp.owneruserid as user_id,
    ta.tagname,
    count(*) as tag_posts,
    sum(coalesce(rp.score,0)) as tag_score,
    row_number() over (partition by rp.owneruserid order by count(*) desc, sum(coalesce(rp.score,0)) desc) as rn
  from recent_posts rp
  cross join lateral unnest(rp.tag_array) as t(tagname)
  left join tags ta on ta.tagname = t.tagname
  where rp.owneruserid is not null
  group by rp.owneruserid, ta.tagname
),
-- consolidated per-user rollup across posts, votes, comments
user_rollup as (
  select
    ru.user_id,
    ru.displayname,
    ru.norm_location,
    ru.website_host,
    ru.reputation,
    ru.upvotes,
    ru.downvotes,
    ru.views,
    -- aggregate across all posts in window
    sum(coalesce(upm.post_cnt,0)) as total_posts,
    sum(coalesce(upm.total_views,0)) as total_post_views,
    sum(coalesce(upm.total_score,0)) as total_post_score,
    avg(coalesce(upm.avg_score,0)) filter (where upm.posttypeid in (1,2)) as avg_score_q_a,
    max(upm.p90_score) as max_p90_score,
    max(upm.last_post_date) as last_post_date
  from recent_users ru
  left join user_post_metrics upm
    on upm.user_id = ru.user_id
  group by ru.user_id, ru.displayname, ru.norm_location, ru.website_host, ru.reputation, ru.upvotes, ru.downvotes, ru.views
),
-- compute per-user interaction with votes/comments via correlated subqueries
user_interactions as (
  select
    ur.user_id,
    -- total received votes on user's posts
    coalesce((
      select sum(va.total_votes)
      from vote_agg va
      join posts p on p.id = va.postid
      where p.owneruserid = ur.user_id
    ), 0) as received_votes,
    coalesce((
      select sum(va.up_cnt) - sum(va.down_cnt)
      from vote_agg va
      join posts p on p.id = va.postid
      where p.owneruserid = ur.user_id
    ), 0) as net_votes,
    -- best commenter on user's posts
    (
      select c.userid
      from comment_scores c
      join posts p on p.id = c.postid
      where p.owneruserid = ur.user_id and c.userid is not null
      order by sum(c.comment_score) over (partition by c.userid) desc nulls last,
               sum(c.comment_count) over (partition by c.userid) desc,
               max(c.last_comment_date) over (partition by c.userid) desc
      limit 1
    ) as top_commenter_userid
  from user_rollup ur
),
-- combine with badges to get diversity
badge_summary as (
  select
    b.userid as user_id,
    count(*) as badges_total,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    count(distinct b.name) as unique_badges,
    count(*) filter (where b.tagbased = 1) as tag_badges
  from badges b
  where b.date >= now() - interval '730 days'
  group by b.userid
),
-- rank users by composite score using window function
user_ranked as (
  select
    ur.*,
    ui.received_votes,
    ui.net_votes,
    ui.top_commenter_userid,
    coalesce(bs.badges_total,0) as badges_total,
    coalesce(bs.gold_badges,0) as gold_badges,
    coalesce(bs.silver_badges,0) as silver_badges,
    coalesce(bs.bronze_badges,0) as bronze_badges,
    coalesce(bs.unique_badges,0) as unique_badges,
    coalesce(bs.tag_badges,0) as tag_badges,
    -- composite score with various weights and null handling
    (
      coalesce(ur.total_post_score,0) * 1.0
      + coalesce(ur.total_post_views,0) * 0.01
      + coalesce(ui.net_votes,0) * 2.0
      + coalesce(bs.gold_badges,0) * 10.0
      + coalesce(bs.silver_badges,0) * 4.0
      + coalesce(bs.bronze_badges,0) * 1.5
      + greatest(0, extract(epoch from (now() - coalesce(ur.last_post_date, now() - interval '10 years'))) / 86400.0 * -0.05)
    ) as composite_score,
    row_number() over (
      order by
        (
          coalesce(ur.total_post_score,0) * 1.0
          + coalesce(ur.total_post_views,0) * 0.01
          + coalesce(ui.net_votes,0) * 2.0
          + coalesce(bs.gold_badges,0) * 10.0
          + coalesce(bs.silver_badges,0) * 4.0
          + coalesce(bs.bronze_badges,0) * 1.5
          + greatest(0, extract(epoch from (now() - coalesce(ur.last_post_date, now() - interval '10 years'))) / 86400.0 * -0.05)
        ) desc,
        ur.reputation desc,
        ur.views desc
    ) as user_rank
  from user_rollup ur
  left join user_interactions ui on ui.user_id = ur.user_id
  left join badge_summary bs on bs.user_id = ur.user_id
),
-- collect question-level features joining everything
question_facts as (
  select
    rp.id as question_id,
    rp.owneruserid as asker_id,
    ru.displayname as asker_name,
    rp.score as q_score,
    rp.viewcount as q_views,
    rp.answercount as q_answers,
    rp.commentcount as q_comments,
    rp.favoritecount as q_favs,
    rp.creationdate as q_created,
    rp.closeddate,
    crm.last_close_reason_name,
    pls.dup_links,
    pls.related_links,
    pls.all_links,
    pls.distinct_related,
    -- tag composition string
    array_to_string(rp.tag_array, ',') as tags_csv,
    -- acceptance: whether has accepted answer id present via self FK
    case when rp.posttypeid = 1 and rp.acceptedanswerid is not null then 1 else 0 end as has_accepted,
    -- hottest tag popularity among its tags
    (
      select min(tr.popularity_rank)
      from unnest(rp.tag_array) t(tagname)
      join tag_rank tr on tr.tagname = t.tagname
    ) as best_tag_rank
  from recent_posts rp
  left join recent_users ru on ru.user_id = rp.owneruserid
  left join closure_reason_map crm on crm.postid = rp.id
  left join post_link_stats pls on pls.postid = rp.id
  where rp.posttypeid = 1
),
-- derive answerer impact via correlated subquery
answer_impact as (
  select
    qf.question_id,
    coalesce((
      select sum(a.score)
      from posts a
      where a.parentid = qf.question_id
        and a.posttypeid = 2
    ), 0) as sum_answer_scores,
    coalesce((
      select max(a.score)
      from posts a
      where a.parentid = qf.question_id
        and a.posttypeid = 2
    ), 0) as max_answer_score,
    coalesce((
      select count(*)
      from posts a
      where a.parentid = qf.question_id
        and a.posttypeid = 2
        and a.owneruserid in (
          select user_id from user_ranked where user_rank <= 50
        )
    ), 0) as answers_by_top50
  from question_facts qf
),
-- final selection with set operator to incorporate some older high-score questions
candidate_questions as (
  select
    qf.*,
    ai.sum_answer_scores,
    ai.max_answer_score,
    ai.answers_by_top50
  from question_facts qf
  join answer_impact ai on ai.question_id = qf.question_id

  union all

  select
    qf.*,
    ai.sum_answer_scores,
    ai.max_answer_score,
    ai.answers_by_top50
  from (
    select p.*
    from posts p
    where p.posttypeid = 1
      and p.creationdate < now() - interval '730 days'
      and p.score >= 50
  ) oldq
  join question_facts qf on qf.question_id = oldq.id
  join answer_impact ai on ai.question_id = qf.question_id
),
-- compute per-question rank within tag popularity and closure state
question_ranked as (
  select
    cq.*,
    case when cq.closeddate is null then 0 else 1 end as is_closed,
    row_number() over (
      partition by coalesce(cq.best_tag_rank, 999999)
      order by
        (coalesce(cq.q_score,0) + coalesce(cq.sum_answer_scores,0)) desc,
        coalesce(cq.q_views,0) desc,
        cq.q_created desc
    ) as rank_within_tagbucket
  from candidate_questions cq
)
select
  ur.user_rank,
  ur.user_id,
  ur.displayname,
  ur.norm_location,
  ur.website_host,
  ur.reputation,
  ur.total_posts,
  ur.total_post_views,
  ur.total_post_score,
  ur.avg_score_q_a,
  ur.badges_total,
  ur.gold_badges,
  ur.silver_badges,
  ur.bronze_badges,
  ur.unique_badges,
  ur.tag_badges,
  ur.received_votes,
  ur.net_votes,
  ur.composite_score,
  utt.tagname as top_tag,
  utt.tag_posts as top_tag_posts,
  -- aggregated question highlights for the user
  qh.question_id,
  qh.q_score,
  qh.q_views,
  qh.q_answers,
  qh.q_comments,
  qh.q_favs,
  qh.tags_csv,
  qh.last_close_reason_name,
  qh.dup_links,
  qh.related_links,
  qh.all_links,
  qh.distinct_related,
  qh.sum_answer_scores,
  qh.max_answer_score,
  qh.answers_by_top50,
  qh.rank_within_tagbucket
from user_ranked ur
left join user_top_tags utt
  on utt.user_id = ur.user_id and utt.rn = 1
left join lateral (
  select
    qr.*
  from question_ranked qr
  where qr.asker_id = ur.user_id
  order by
    (coalesce(qr.q_score,0) + coalesce(qr.sum_answer_scores,0)) desc,
    coalesce(qr.q_views,0) desc nulls last,
    qr.q_created desc
  limit 3
) qh on true
where ur.user_rank <= 100
order by ur.user_rank, qh.rank_within_tagbucket nulls last;