-- {"query": "442.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2676} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    row_number() over (order by u.reputation desc, u.id) as rn_global
  from users u
  left join badges b
    on b.userid = u.id
   and b.date >= u.creationdate
  where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from users)
  group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.websiteurl
), user_posts as (
  select
    p.owneruserid as user_id,
    p.posttypeid,
    count(*) as posts,
    sum(coalesce(p.viewcount, 0)) as total_views,
    sum(coalesce(p.score, 0)) as total_score,
    sum(case when p.posttypeid = 1 then coalesce(p.answercount, 0) else 0 end) as answers_received,
    sum(case when p.posttypeid = 2 then 1 else 0 end) as answers_authored
  from posts p
  where p.owneruserid is not null
    and p.owneruserid > 0
    and p.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from posts)
  group by p.owneruserid, p.posttypeid
), user_post_agg as (
  select
    user_id,
    sum(posts) as post_count,
    sum(total_views) as view_count,
    sum(total_score) as score_sum,
    sum(answers_received) as answers_received,
    sum(answers_authored) as answers_authored,
    max(case when posttypeid = 1 then posts end) as question_count,
    max(case when posttypeid = 2 then posts end) as answer_count
  from user_posts
  group by user_id
), last_activity as (
  select
    p.owneruserid as user_id,
    max(p.lastactivitydate) as last_post_activity,
    max(p.lasteditdate) as last_post_edit
  from posts p
  where p.owneruserid is not null and p.owneruserid > 0
  group by p.owneruserid
), vote_agg as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as up_votes_made,
    count(*) filter (where v.votetypeid = 3) as down_votes_made,
    count(*) filter (where v.votetypeid = 5) as favorites_made,
    sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total
  from votes v
  where v.userid is not null
  group by v.userid
), post_vote_agg as (
  select
    p.owneruserid as user_id,
    count(*) filter (where v.votetypeid = 2) as up_votes_received,
    count(*) filter (where v.votetypeid = 3) as down_votes_received
  from posts p
  left join votes v
    on v.postid = p.id
  where p.owneruserid is not null and p.owneruserid > 0
  group by p.owneruserid
), comments_agg as (
  select
    coalesce(c.userid, -1) as user_id,
    count(*) as comments_authored,
    sum(coalesce(c.score,0)) as comment_score_sum,
    max(c.creationdate) as last_comment_date
  from comments c
  group by coalesce(c.userid, -1)
), tag_extract as (
  select
    p.id as post_id,
    p.owneruserid as user_id,
    unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tagname
  from posts p
  where p.posttypeid = 1
    and p.tags is not null
    and length(p.tags) > 2
), user_top_tags as (
  select
    t.user_id,
    t.tagname,
    count(*) as tag_uses,
    row_number() over (partition by t.user_id order by count(*) desc, t.tagname) as tag_rank
  from tag_extract t
  group by t.user_id, t.tagname
), duplicates_closed as (
  select
    ph.postid as question_id,
    max(ph.creationdate) as last_closed_duplicate
  from posthistory ph
  where ph.posthistorytypeid = 10
    and ph.comment in ('1','101') -- legacy and current duplicate reasons
  group by ph.postid
), link_dupes as (
  select
    pl.postid as question_id,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links
  from postlinks pl
  group by pl.postid
), accepted_rate as (
  select
    a.owneruserid as user_id,
    count(*) as answers_total,
    count(*) filter (where a.id = q.acceptedanswerid) as answers_accepted
  from posts a
  join posts q on q.id = a.parentid
  where a.posttypeid = 2
  group by a.owneruserid
), activity_streaks as (
  select user_id, max(streak_len) as max_streak
  from (
    select
      u.id as user_id,
      count(*) as streak_len
    from users u
    join lateral (
      select date_trunc('day', x.d)::date as d
      from generate_series(u.creationdate::date, coalesce(u.lastaccessdate::date, now()::date), interval '1 day') as x(d)
    ) days on true
    left join (
      select p.owneruserid as user_id, date_trunc('day', p.creationdate)::date as d
      from posts p
      where p.owneruserid is not null and p.owneruserid > 0
    ) up on up.user_id = u.id and up.d = days.d
    where up.user_id is not null
    group by u.id
  ) s
  group by user_id
), user_ranked as (
  select
    ru.*,
    upa.post_count,
    upa.view_count,
    upa.score_sum,
    upa.answers_received,
    upa.answers_authored,
    coalesce(upa.question_count,0) as question_count,
    coalesce(upa.answer_count,0) as answer_count,
    la.last_post_activity,
    la.last_post_edit,
    va.up_votes_made,
    va.down_votes_made,
    va.favorites_made,
    va.bounty_total,
    pva.up_votes_received,
    pva.down_votes_received,
    ca.comments_authored,
    ca.comment_score_sum,
    ca.last_comment_date,
    ar.answers_total,
    ar.answers_accepted,
    case when coalesce(ar.answers_total,0) = 0 then null
         else round(100.0 * ar.answers_accepted / nullif(ar.answers_total,0), 2)
    end as accept_rate_pct,
    ds.last_closed_duplicate,
    ld.duplicate_links,
    ats.max_streak,
    dense_rank() over (order by coalesce(upa.score_sum,0) + coalesce(pva.up_votes_received,0)*2 - coalesce(pva.down_votes_received,0) desc, ru.reputation desc) as perf_rank
  from recent_users ru
  left join user_post_agg upa on upa.user_id = ru.user_id
  left join last_activity la on la.user_id = ru.user_id
  left join vote_agg va on va.user_id = ru.user_id
  left join post_vote_agg pva on pva.user_id = ru.user_id
  left join comments_agg ca on ca.user_id = ru.user_id
  left join accepted_rate ar on ar.user_id = ru.user_id
  left join duplicates_closed ds on ds.question_id in (
    select id from posts where owneruserid = ru.user_id and posttypeid = 1
  )
  left join link_dupes ld on ld.question_id in (
    select id from posts where owneruserid = ru.user_id and posttypeid = 1
  )
  left join activity_streaks ats on ats.user_id = ru.user_id
), top_tag_pivot as (
  select
    utt.user_id,
    max(case when utt.tag_rank = 1 then utt.tagname end) as top_tag_1,
    max(case when utt.tag_rank = 2 then utt.tagname end) as top_tag_2,
    max(case when utt.tag_rank = 3 then utt.tagname end) as top_tag_3
  from user_top_tags utt
  where utt.tag_rank <= 3
  group by utt.user_id
), final_scored as (
  select
    ur.*,
    ttp.top_tag_1,
    ttp.top_tag_2,
    ttp.top_tag_3,
    -- composite performance score with mixed signals
    (
      coalesce(ur.score_sum,0)*1.0
      + coalesce(ur.up_votes_received,0)*1.5
      - coalesce(ur.down_votes_received,0)*0.5
      + coalesce(ur.view_count,0)*0.001
      + coalesce(ur.answers_accepted,0)*2.0
      + coalesce(ur.gold_badges,0)*5
      + coalesce(ur.silver_badges,0)*2
      + coalesce(ur.bronze_badges,0)*1
      + case when coalesce(ur.accept_rate_pct,0) >= 60 then 10 else 0 end
      + case when coalesce(ur.question_count,0) > 0 and coalesce(ur.duplicate_links,0) > 0 then -2 else 0 end
      + least(coalesce(ur.max_streak,0), 30)*0.2
    ) as perf_score
  from user_ranked ur
  left join top_tag_pivot ttp on ttp.user_id = ur.user_id
)
select
  fs.user_id,
  coalesce(nullif(fs.displayname,''), concat('user#', fs.user_id::text)) as displayname,
  fs.reputation,
  to_char(fs.creationdate, 'YYYY-MM-DD') as joined,
  coalesce(fs.location, 'Unknown') as location,
  fs.websiteurl,
  fs.gold_badges || '/' || fs.silver_badges || '/' || fs.bronze_badges as badges_g_s_b,
  coalesce(fs.question_count,0) as question_count,
  coalesce(fs.answer_count,0) as answer_count,
  coalesce(fs.post_count,0) as post_count,
  coalesce(fs.view_count,0) as view_count,
  coalesce(fs.score_sum,0) as score_sum,
  coalesce(fs.up_votes_received,0) as up_rcv,
  coalesce(fs.down_votes_received,0) as dn_rcv,
  coalesce(fs.up_votes_made,0) as up_made,
  coalesce(fs.down_votes_made,0) as dn_made,
  coalesce(fs.favorites_made,0) as favs_made,
  coalesce(fs.bounty_total,0) as bounty_total,
  coalesce(fs.comments_authored,0) as comments_authored,
  coalesce(fs.comment_score_sum,0) as comment_score_sum,
  fs.last_post_activity,
  fs.last_post_edit,
  fs.last_comment_date,
  fs.answers_total,
  fs.answers_accepted,
  fs.accept_rate_pct,
  fs.top_tag_1,
  fs.top_tag_2,
  fs.top_tag_3,
  fs.perf_rank,
  round(fs.perf_score::numeric, 2) as perf_score
from final_scored fs
qualify row_number() over (
  order by fs.perf_score desc nulls last, fs.perf_rank, fs.user_id
) <= 250
order by fs.perf_score desc nulls last, fs.perf_rank, fs.user_id;