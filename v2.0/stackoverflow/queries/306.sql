with recent_activity as (
  select
    p.id as post_id,
    p.posttypeid,
    p.owneruserid,
    p.score,
    p.viewcount,
    p.creationdate,
    p.lastactivitydate,
    p.tags,
    p.title,
    u.displayname as owner_name,
    u.reputation,
    coalesce(p.favoritecount, 0) as favoritecount
  from posts p
  left join users u on u.id = p.owneruserid
  where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
tag_unpacked as (
  select
    ra.post_id,
    unnest(string_to_array(substring(ra.tags, 2, greatest(length(ra.tags)-2,0)), '><')) as tagname
  from recent_activity ra
  where ra.posttypeid = 1
),
tag_stats as (
  select
    tu.post_id,
    count(case when lower(tu.tagname) in ('sql','postgresql','mysql','tsql','sqlite') then 1 end) as tag_is_sql_family,
    count(*) as tag_count
  from tag_unpacked tu
  group by tu.post_id
),
vote_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    count(case when v.votetypeid in (8,9) then 1 end) as bounty_events,
    max(v.creationdate) as last_vote_at
  from votes v
  group by v.postid
),
comment_agg as (
  select
    c.postid,
    count(*) as comment_count,
    max(c.creationdate) as last_comment_at,
    max(length(c.text)) as max_comment_len,
    sum(case when c.score > 0 then 1 else 0 end) as positive_comments
  from comments c
  group by c.postid
),
link_agg as (
  select
    pl.postid,
    count(case when pl.linktypeid = 1 then 1 end) as linked_count,
    count(case when pl.linktypeid = 3 then 1 end) as duplicate_links
  from postlinks pl
  group by pl.postid
),
close_events as (
  select
    ph.postid,
    count(case when ph.posthistorytypeid = 10 then 1 end) as close_events,
    min(case when ph.posthistorytypeid = 10 then ph.creationdate end) as first_closed_at,
    max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as last_reopened_at,
    bool_or(ph.posthistorytypeid = 19) as ever_protected
  from posthistory ph
  where ph.posthistorytypeid in (10,11,19)
  group by ph.postid
),
answer_rel as (
  select
    q.id as question_id,
    a.id as answer_id,
    a.owneruserid as answer_ownerid,
    a.score as answer_score,
    a.creationdate as answer_created
  from posts q
  join posts a on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
),
answer_rank as (
  select
    ar.*,
    rank() over (partition by ar.question_id order by ar.answer_score desc nulls last, ar.answer_created asc) as score_rank,
    row_number() over (partition by ar.question_id order by ar.answer_created asc) as age_rank
  from answer_rel ar
),
best_and_first as (
  select
    question_id,
    max(case when score_rank = 1 then answer_id end) as top_answer_id,
    max(case when score_rank = 1 then answer_score end) as top_answer_score,
    max(case when age_rank = 1 then answer_id end) as first_answer_id,
    max(case when age_rank = 1 then answer_ownerid end) as first_answer_ownerid
  from answer_rank
  group by question_id
),
user_badge_agg as (
  select
    b.userid,
    count(*) as badges_total,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
post_popularity as (
  select
    ra.post_id,
    (coalesce(va.upvotes,0) - coalesce(va.downvotes,0)) as net_votes,
    ra.viewcount,
    ra.favoritecount,
    coalesce(va.bounty_events,0) as bounty_events,
    coalesce(ca.comment_count,0) as comment_count,
    coalesce(la.linked_count,0) as linked_count,
    coalesce(la.duplicate_links,0) as duplicate_links,
    extract(epoch from (coalesce(ra.lastactivitydate, ra.creationdate) - ra.creationdate)) / 3600.0 as hours_active,
    case when ra.viewcount > 0 then (coalesce(va.upvotes,0) * 1.0 / ra.viewcount) else null end as upvote_view_ratio
  from recent_activity ra
  left join vote_agg va on va.postid = ra.post_id
  left join comment_agg ca on ca.postid = ra.post_id
  left join link_agg la on la.postid = ra.post_id
),
question_enriched as (
  select
    ra.post_id,
    ra.title,
    ra.tags,
    ra.owneruserid,
    ra.owner_name,
    ra.reputation,
    ts.tag_is_sql_family,
    ts.tag_count,
    pp.net_votes,
    pp.viewcount,
    pp.favoritecount,
    pp.bounty_events,
    pp.comment_count,
    pp.linked_count,
    pp.duplicate_links,
    pp.hours_active,
    pp.upvote_view_ratio,
    ce.close_events,
    ce.first_closed_at,
    ce.last_reopened_at,
    ce.ever_protected,
    ba.top_answer_id,
    ba.top_answer_score,
    ba.first_answer_id,
    ba.first_answer_ownerid
  from recent_activity ra
  left join tag_stats ts on ts.post_id = ra.post_id
  left join post_popularity pp on pp.post_id = ra.post_id
  left join close_events ce on ce.postid = ra.post_id
  left join best_and_first ba on ba.question_id = ra.post_id
  where ra.posttypeid = 1
),
user_enriched as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate as user_created,
    u.lastaccessdate as user_lastseen,
    coalesce(uba.badges_total,0) as badges_total,
    coalesce(uba.gold_badges,0) as gold_badges,
    coalesce(uba.silver_badges,0) as silver_badges,
    coalesce(uba.bronze_badges,0) as bronze_badges,
    uba.last_badge_at
  from users u
  left join user_badge_agg uba on uba.userid = u.id
),
recent_dupe_targets as (
  select
    pl.relatedpostid as target_id,
    count(*) as dupes_pointing_here,
    max(pl.creationdate) as last_dupe_at
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.relatedpostid
),
nullability_probe as (
  select
    qe.post_id,
    case
      when qe.tag_count is null and qe.tags is null then 'no-tags'
      when qe.tag_count is null and qe.tags is not null then 'embedded'
      else 'counted'
    end as tag_status,
    case when qe.top_answer_id is null then 1 else 0 end as no_top_answer,
    case when qe.first_answer_id is null then 1 else 0 end as no_first_answer
  from question_enriched qe
),
scored as (
  select
    qe.*,
    ue.displayname as asker_name,
    ue.badges_total,
    ue.gold_badges,
    ue.silver_badges,
    ue.bronze_badges,
    rdt.dupes_pointing_here,
    rdt.last_dupe_at,
    np.tag_status,
    np.no_top_answer,
    np.no_first_answer,
    (
      coalesce(qe.net_votes,0)*2
      + coalesce(qe.favoritecount,0)
      + coalesce(qe.comment_count,0)*0.25
      + coalesce(qe.linked_count,0)*0.5
      - coalesce(qe.duplicate_links,0)*1.5
      + coalesce(qe.tag_is_sql_family,0)*3
      + case when qe.ever_protected then -2 else 0 end
      + case when qe.close_events > 0 then -3 else 0 end
      + case when qe.upvote_view_ratio is null then 0 else least(qe.upvote_view_ratio*100, 10) end
      + least(coalesce(rdt.dupes_pointing_here,0), 5)
    ) as composite_score
  from question_enriched qe
  left join user_enriched ue on ue.user_id = qe.owneruserid
  left join recent_dupe_targets rdt on rdt.target_id = qe.post_id
  left join nullability_probe np on np.post_id = qe.post_id
),
ranked as (
  select
    s.*,
    ntile(10) over (order by s.composite_score desc nulls last) as decile,
    row_number() over (order by s.composite_score desc nulls last, s.viewcount desc nulls last, s.net_votes desc nulls last) as global_rank
  from scored s
)
select
  r.global_rank,
  r.decile,
  r.post_id,
  substring(coalesce(r.title,''), 1, 120) as title_preview,
  r.tags,
  coalesce(r.net_votes,0) as net_votes,
  coalesce(r.viewcount,0) as views,
  coalesce(r.favoritecount,0) as favorites,
  coalesce(r.comment_count,0) as comments,
  coalesce(r.linked_count,0) as links,
  coalesce(r.duplicate_links,0) as dup_links,
  coalesce(r.dupes_pointing_here,0) as dup_targets,
  r.composite_score,
  r.tag_is_sql_family,
  r.tag_count,
  r.close_events,
  coalesce(r.ever_protected,false) as ever_protected,
  r.upvote_view_ratio,
  r.hours_active,
  r.top_answer_id,
  r.top_answer_score,
  r.first_answer_id,
  r.first_answer_ownerid,
  r.asker_name,
  r.badges_total,
  r.gold_badges,
  r.silver_badges,
  r.bronze_badges,
  r.last_dupe_at,
  r.first_closed_at,
  r.last_reopened_at,
  r.owneruserid as asker_id,
  r.no_top_answer,
  r.no_first_answer
from ranked r
where (
    coalesce(r.tag_is_sql_family,0) > 0
    or coalesce(r.net_votes,0) >= 5
    or (coalesce(r.duplicate_links,0) > 0 and coalesce(r.dupes_pointing_here,0) > 0)
    or (coalesce(r.close_events,0) > 0 and r.last_reopened_at is not null)
  )
  and not (r.no_top_answer = 1 and r.no_first_answer = 1)
order by r.global_rank
limit 200;