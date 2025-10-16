with recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.creationdate,
    p.owneruserid,
    p.title,
    p.tags,
    p.score,
    p.viewcount,
    coalesce(nullif(trim(p.ownerdisplayname), ''), u.displayname, '[unknown]') as owner_name,
    case when p.posttypeid = 1 then 'Question' when p.posttypeid = 2 then 'Answer' else 'Other' end as post_type_name
  from posts p
  left join users u on u.id = p.owneruserid
  where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
post_vote_agg as (
  select
    v.postid,
    count(*) filter (where v.votetypeid = 2) as upvotes,
    count(*) filter (where v.votetypeid = 3) as downvotes,
    count(*) filter (where v.votetypeid = 5) as favorites,
    sum(coalesce(v.bountyamount, 0)) as bounty_total,
    min(v.creationdate) as first_vote_at,
    max(v.creationdate) as last_vote_at
  from votes v
  group by v.postid
),
post_comment_agg as (
  select
    c.postid,
    count(*) as comment_count,
    max(c.creationdate) as last_commented_at,
    max(length(c.text)) as longest_comment_len,
    sum(case when c.userdisplayname is null and c.userid is null then 1 else 0 end) as anon_comment_count
  from comments c
  group by c.postid
),
post_links_agg as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 1) as linked_count,
    count(*) filter (where pl.linktypeid = 3) as duplicate_of_count,
    count(distinct pl.relatedpostid) as distinct_related_count
  from postlinks pl
  group by pl.postid
),
question_tag as (
  select
    p.id as postid,
    unnest(string_to_array(substring(p.tags, 2, length(p.tags) - 2), '><')) as tagname
  from posts p
  where p.posttypeid = 1
    and p.tags is not null
    and length(p.tags) > 2
),
tag_quality as (
  select
    qt.tagname,
    count(*) as q_count,
    avg(cast(p.score as numeric)) as avg_q_score,
    percentile_cont(0.9) within group (order by p.viewcount) as p90_views
  from question_tag qt
  join posts p on p.id = qt.postid
  group by qt.tagname
),
user_activity as (
  select
    u.id as userid,
    u.displayname,
    u.reputation,
    u.creationdate as user_created,
    u.lastaccessdate,
    u.upvotes,
    u.downvotes,
    u.views as profile_views,
    count(distinct p.id) filter (where p.posttypeid = 1) as questions_posted,
    count(distinct p.id) filter (where p.posttypeid = 2) as answers_posted,
    count(distinct b.id) filter (where b.class = 1) as gold_badges,
    count(distinct b.id) filter (where b.class = 2) as silver_badges,
    count(distinct b.id) filter (where b.class = 3) as bronze_badges,
    max(b.date) as last_badge_date
  from users u
  left join posts p on p.owneruserid = u.id
  left join badges b on b.userid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, u.upvotes, u.downvotes, u.views
),
edit_events as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
    count(*) filter (where ph.posthistorytypeid in (24)) as suggested_edits_applied,
    count(*) filter (where ph.posthistorytypeid in (10)) as close_events,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,24)) as last_edit_at,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (10)) as last_closed_at,
    max(
      case
        when ph.posthistorytypeid = 10
        then nullif(ph.comment, '')
        else null
      end
    ) as last_close_reason_id_raw
  from posthistory ph
  group by ph.postid
),
close_reason as (
  select
    ph.postid,
    crt.name as close_reason_name,
    ph.creationdate as close_date
  from posthistory ph
  join closeReasonTypes crt on crt.id = cast(nullif(ph.comment, '') as integer)
  where ph.posthistorytypeid = 10
    and ph.comment ~ '^[0-9]+$'
),
answer_accepts as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    case when q.acceptedanswerid = a.id then 1 else 0 end as is_accepted
  from posts a
  join posts q on q.id = a.parentid
  where a.posttypeid = 2
),
question_answer_stats as (
  select
    q.id as question_id,
    count(*) as answers_count,
    sum(is_accepted) as accepted_count
  from answer_accepts aa
  join posts q on q.id = aa.question_id
  group by q.id
),
recent_question_rank as (
  select
    rp.id as postid,
    rp.title,
    rp.owner_name,
    rp.creationdate,
    rp.viewcount,
    rp.score,
    qa.answers_count,
    qa.accepted_count,
    row_number() over (partition by date_trunc('month', rp.creationdate) order by rp.score desc, rp.viewcount desc, rp.id) as rn_month_score,
    dense_rank() over (order by rp.viewcount desc) as rank_by_views_overall
  from recent_posts rp
  left join question_answer_stats qa on qa.question_id = rp.id
  where rp.posttypeid = 1
),
owner_baseline as (
  select
    rp.owneruserid,
    count(*) as owner_post_count,
    min(rp.creationdate) as first_post_at,
    max(rp.creationdate) as last_post_at,
    avg(cast(rp.score as numeric)) as avg_owner_score
  from recent_posts rp
  where rp.owneruserid is not null
  group by rp.owneruserid
),
null_owner_posts as (
  select
    rp.id
  from recent_posts rp
  left join users u on u.id = rp.owneruserid
  where rp.owneruserid is null
     or u.id is null
),
final_union as (
  select
    rp.id as post_id,
    rp.post_type_name,
    coalesce(rp.title, '[no title]') as title,
    rp.owner_name,
    rp.creationdate,
    rp.viewcount,
    rp.score,
    pva.upvotes,
    pva.downvotes,
    pva.favorites,
    pva.bounty_total,
    pca.comment_count,
    pca.anon_comment_count,
    pla.linked_count,
    pla.duplicate_of_count,
    ee.edit_count,
    ee.suggested_edits_applied,
    ee.last_edit_at,
    cr.close_reason_name,
    rqr.rn_month_score,
    rqr.rank_by_views_overall,
    ob.avg_owner_score,
    tq_top.tagname as top_tag_by_quality,
    tq_top.avg_q_score as top_tag_avg_score,
    case
      when rp.posttypeid = 1 and coalesce(qa.answers_count, 0) = 0 then 'Unanswered'
      when rp.posttypeid = 1 and coalesce(qa.accepted_count, 0) = 0 then 'Unaccepted'
      when rp.posttypeid = 1 then 'Resolved'
      when rp.posttypeid = 2 then 'Answer'
      else 'Other'
    end as resolution_state,
    case when nlp.id is not null then 1 else 0 end as has_missing_owner_flag
  from recent_posts rp
  left join post_vote_agg pva on pva.postid = rp.id
  left join post_comment_agg pca on pca.postid = rp.id
  left join post_links_agg pla on pla.postid = rp.id
  left join edit_events ee on ee.postid = rp.id
  left join close_reason cr on cr.postid = rp.id
  left join recent_question_rank rqr on rqr.postid = rp.id
  left join question_answer_stats qa on qa.question_id = rp.id
  left join owner_baseline ob on ob.owneruserid = rp.owneruserid
  left join lateral (
    select tq.tagname, tq.avg_q_score
    from question_tag qt
    join tag_quality tq on tq.tagname = qt.tagname
    where qt.postid = rp.id
    order by tq.avg_q_score desc nulls last, tq.q_count desc
    limit 1
  ) as tq_top on true
  left join null_owner_posts nlp on nlp.id = rp.id

  union all

  select
    q.id as post_id,
    'QuestionWithNoRecentVotes' as post_type_name,
    coalesce(q.title, '[no title]') as title,
    coalesce(nullif(trim(q.ownerdisplayname), ''), '[unknown]') as owner_name,
    q.creationdate,
    q.viewcount,
    q.score,
    0 as upvotes,
    0 as downvotes,
    0 as favorites,
    0 as bounty_total,
    0 as comment_count,
    0 as anon_comment_count,
    0 as linked_count,
    0 as duplicate_of_count,
    0 as edit_count,
    0 as suggested_edits_applied,
    null as last_edit_at,
    null as close_reason_name,
    null as rn_month_score,
    null as rank_by_views_overall,
    null as avg_owner_score,
    null as top_tag_by_quality,
    null as top_tag_avg_score,
    'Unknown' as resolution_state,
    case when q.owneruserid is null then 1 else 0 end as has_missing_owner_flag
  from posts q
  where q.posttypeid = 1
    and not exists (select 1 from votes v where v.postid = q.id and v.creationdate >= q.creationdate - interval '7 days')
    and q.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
ranked as (
  select
    f.post_id,
    f.post_type_name,
    f.title,
    f.owner_name,
    f.creationdate,
    f.viewcount,
    f.score,
    f.upvotes,
    f.downvotes,
    f.favorites,
    f.bounty_total,
    f.comment_count,
    f.anon_comment_count,
    f.linked_count,
    f.duplicate_of_count,
    f.edit_count,
    f.suggested_edits_applied,
    f.last_edit_at,
    f.close_reason_name,
    f.rn_month_score,
    f.rank_by_views_overall,
    f.avg_owner_score,
    f.top_tag_by_quality,
    f.top_tag_avg_score,
    f.resolution_state,
    f.has_missing_owner_flag,
    row_number() over (order by coalesce(f.upvotes,0) - coalesce(f.downvotes,0) desc, coalesce(f.viewcount,0) desc, f.creationdate desc, f.post_id) as rownum_global,
    sum(case when f.has_missing_owner_flag = 1 then 1 else 0 end) over () as total_missing_owners
  from final_union f
),
outliers as (
  select
    r.post_id,
    r.post_type_name,
    r.title,
    r.owner_name,
    r.creationdate,
    r.viewcount,
    r.score,
    r.upvotes,
    r.downvotes,
    r.favorites,
    r.bounty_total,
    r.comment_count,
    r.anon_comment_count,
    r.linked_count,
    r.duplicate_of_count,
    r.edit_count,
    r.suggested_edits_applied,
    r.last_edit_at,
    r.close_reason_name,
    r.rn_month_score,
    r.rank_by_views_overall,
    r.avg_owner_score,
    r.top_tag_by_quality,
    r.top_tag_avg_score,
    r.resolution_state,
    r.has_missing_owner_flag,
    r.rownum_global,
    r.total_missing_owners,
    case
      when coalesce(r.viewcount,0) > (
        select coalesce(avg(viewcount),0) + 3 * coalesce(stddev_pop(viewcount),0) from ranked
      ) then 1 else 0
    end as is_view_outlier
  from ranked r
)
select
  o.post_id,
  o.post_type_name,
  o.title,
  o.owner_name,
  o.creationdate,
  o.viewcount,
  o.score,
  o.upvotes,
  o.downvotes,
  o.favorites,
  o.bounty_total,
  o.comment_count,
  o.anon_comment_count,
  o.linked_count,
  o.duplicate_of_count,
  o.edit_count,
  o.suggested_edits_applied,
  o.last_edit_at,
  o.close_reason_name,
  o.rn_month_score,
  o.rank_by_views_overall,
  o.avg_owner_score,
  o.top_tag_by_quality,
  o.top_tag_avg_score,
  o.resolution_state,
  o.has_missing_owner_flag,
  o.rownum_global,
  o.total_missing_owners,
  o.is_view_outlier,
  case
    when o.upvotes is null and o.downvotes is null then 'NoVotes'
    when coalesce(o.upvotes,0) - coalesce(o.downvotes,0) >= 10 then 'Hot'
    when coalesce(o.upvotes,0) - coalesce(o.downvotes,0) <= -3 then 'Controversial'
    else 'Normal'
  end as popularity_bucket
from outliers o
where
  (
    (o.post_type_name in ('Question','Answer') and coalesce(o.upvotes,0) + coalesce(o.downvotes,0) >= 5)
    or (o.post_type_name = 'QuestionWithNoRecentVotes' and coalesce(o.viewcount,0) >= 10)
  )
  and coalesce(o.title, '') not ilike '%test%'
order by
  popularity_bucket,
  o.rn_month_score nulls last,
  o.rank_by_views_overall nulls last,
  o.rownum_global
limit 500;