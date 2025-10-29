with recent_activity as (
  select
    p.id as post_id,
    p.posttypeid,
    p.creationdate,
    p.owneruserid,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.acceptedanswerid,
    p.parentid,
    p.lastactivitydate,
    coalesce(p.answercount, 0) as answercount,
    coalesce(p.commentcount, 0) as commentcount
  from posts p
  where p.creationdate >= (
    select date_trunc('month', max(creationdate)) - interval '6 months' from posts
  )
),
user_aug as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate as user_created,
    u.lastaccessdate,
    u.location,
    u.views as profile_views,
    u.upvotes,
    u.downvotes,
    coalesce(nullif(trim(u.websiteurl), ''), '(none)') as websiteurl_norm
  from users u
),
vote_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid in (2,3) then 1 else 0 end) as total_votes,
    count(*) as raw_vote_events,
    max(v.creationdate) as last_vote_at
  from votes v
  group by v.postid
),
qa as (
  select
    ra.*,
    case when ra.posttypeid = 1 then 'Question'
         when ra.posttypeid = 2 then 'Answer'
         else 'Other' end as posttype_name,
    case when ra.posttypeid = 1 then string_to_array(substring(ra.tags, 2, length(ra.tags)-2), '><') end as tag_array
  from recent_activity ra
),
comment_stats as (
  select
    p.id as post_id,
    coalesce((
      select count(*) from comments c where c.postid = p.id
    ), 0) as comment_count,
    coalesce((
      select max(c2.score) from comments c2 where c2.postid = p.id
    ), 0) as top_comment_score,
    coalesce((
      select avg(c3.score * 1.0) from comments c3 where c3.postid = p.id
    ), 0) as avg_comment_score,
    (
      select c4.text from comments c4
      where c4.postid = p.id
      order by c4.score desc NULLS LAST, c4.creationdate asc
      limit 1
    ) as top_comment_text
  from posts p
  where exists (select 1 from recent_activity ra where ra.post_id = p.id)
),
history_flags as (
  select
    ph.postid,
    sum(case when ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35) then 1 else 0 end) as mod_flag_events,
    sum(case when ph.posthistorytypeid = 10 then 1 else 0 end) as close_events,
    max(case when ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35) then ph.creationdate end) as last_flag_event_at,
    max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_closed_at,
    max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as last_reopened_at,
    max(
      case when ph.posthistorytypeid = 10 then
        nullif(regexp_replace(coalesce(ph.comment, ''), '[^0-9]', '', 'g'), '')
      end
    ) as close_reason_id_text
  from posthistory ph
  group by ph.postid
),
tags_exploded as (
  select
    q.post_id,
    unnest(q.tag_array) as tag_name
  from qa q
  where q.posttypeid = 1
),
tag_meta as (
  select
    te.post_id,
    t.id as tag_id,
    t.tagname,
    t.count as tag_global_count,
    t.ismoderatoronly,
    t.isrequired
  from tags_exploded te
  left join tags t
    on lower(t.tagname) = lower(te.tag_name)
),
link_graph as (
  select
    pl.postid,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_links,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as related_links,
    max(pl.creationdate) as last_link_at
  from postlinks pl
  group by pl.postid
),
user_post_activity as (
  select
    ra.owneruserid as user_id,
    count(*) as recent_posts,
    sum(case when ra.posttypeid = 1 then 1 else 0 end) as recent_questions,
    sum(case when ra.posttypeid = 2 then 1 else 0 end) as recent_answers,
    max(ra.creationdate) as last_post_at
  from recent_activity ra
  where ra.owneruserid is not null
  group by ra.owneruserid
),
answers_enriched as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as answerer_id,
    a.score as answer_score,
    a.creationdate as answer_created,
    q.owneruserid as asker_id,
    q.acceptedanswerid as accepted_answer_id,
    q.score as question_score,
    q.viewcount as question_views
  from posts a
  join posts q on q.id = a.parentid and a.posttypeid = 2 and q.posttypeid = 1
),
answer_windows as (
  select
    ae.*,
    row_number() over (partition by ae.question_id order by ae.answer_score desc NULLS LAST, ae.answer_id) as answer_rank_by_score,
    rank() over (partition by ae.question_id order by ae.answer_created asc) as answer_rank_by_time,
    avg(ae.answer_score) over (partition by ae.question_id) as avg_answer_score_per_q
  from answers_enriched ae
),
post_features as (
  select
    q.post_id,
    q.posttype_name,
    q.creationdate,
    q.owneruserid,
    ua.displayname,
    ua.reputation,
    ua.location,
    ua.websiteurl_norm,
    ua.upvotes as user_upvotes,
    ua.downvotes as user_downvotes,
    ua.profile_views,
    coalesce(va.upvotes, 0) as upvotes,
    coalesce(va.downvotes, 0) as downvotes,
    coalesce(va.favorites, 0) as favorites,
    coalesce(va.total_votes, 0) as total_votes,
    va.last_vote_at,
    cs.comment_count as comments_total,
    cs.top_comment_score,
    cs.avg_comment_score,
    cs.top_comment_text,
    coalesce(hf.mod_flag_events, 0) as mod_flag_events,
    coalesce(hf.close_events, 0) as close_events,
    hf.last_flag_event_at,
    hf.last_closed_at,
    hf.last_reopened_at,
    case when hf.close_reason_id_text = '' or hf.close_reason_id_text is null then null else cast(hf.close_reason_id_text as integer) end as close_reason_id,
    lg.duplicate_links,
    lg.related_links,
    lg.last_link_at,
    upa.recent_posts as user_recent_posts,
    upa.last_post_at as user_last_post_at,
    (coalesce(q.score, 0) * 1.0)
      + (coalesce(va.upvotes, 0) - coalesce(va.downvotes, 0)) * 0.8
      + coalesce(va.favorites, 0) * 1.2
      + coalesce(cs.top_comment_score, 0) * 0.3
      + coalesce(lg.related_links, 0) * 0.5
      - coalesce(lg.duplicate_links, 0) * 2.0
      - case when coalesce(hf.close_events, 0) > 0 then 5.0 else 0.0 end
      + least(
          coalesce(q.viewcount, 0) / nullif(greatest(1, extract(epoch from (timestamp '2024-10-01 12:34:56' - q.creationdate)) / 86400), 0),
          1000
        ) * 0.1
      as composite_engagement_score,
    coalesce(va.total_votes, 0) as total_votes_for_ranking
  from qa q
  left join user_aug ua on ua.user_id = q.owneruserid
  left join vote_agg va on va.postid = q.post_id
  left join comment_stats cs on cs.post_id = q.post_id
  left join history_flags hf on hf.postid = q.post_id
  left join link_graph lg on lg.postid = q.post_id
  left join user_post_activity upa on upa.user_id = q.owneruserid
),
tag_rollup as (
  select
    pm.post_id,
    count(case when tm.tag_id is not null then 1 end) as known_tags,
    sum(coalesce(tm.tag_global_count, 0)) as sum_tag_popularity,
    max(tm.tag_global_count) as max_tag_popularity,
    bool_or(coalesce(tm.ismoderatoronly, false)) as has_moderator_only_tag,
    bool_or(coalesce(tm.isrequired, false)) as has_required_tag,
    string_agg(tm.tagname, ',' ORDER BY tm.tagname) as tag_list_canonical
  from (
    select distinct post_id from post_features
  ) pm
  left join tag_meta tm on tm.post_id = pm.post_id
  group by pm.post_id
),
ranking as (
  select
    pf.post_id,
    pf.posttype_name,
    pf.creationdate,
    pf.owneruserid,
    pf.displayname,
    pf.reputation,
    pf.location,
    pf.websiteurl_norm,
    pf.user_upvotes,
    pf.user_downvotes,
    pf.profile_views,
    pf.upvotes,
    pf.downvotes,
    pf.favorites,
    pf.total_votes,
    pf.last_vote_at,
    pf.comments_total,
    pf.top_comment_score,
    pf.avg_comment_score,
    pf.top_comment_text,
    pf.mod_flag_events,
    pf.close_events,
    pf.last_flag_event_at,
    pf.last_closed_at,
    pf.last_reopened_at,
    pf.close_reason_id,
    pf.duplicate_links,
    pf.related_links,
    pf.last_link_at,
    pf.user_recent_posts,
    pf.user_last_post_at,
    pf.composite_engagement_score,
    tr.known_tags,
    tr.sum_tag_popularity,
    tr.max_tag_popularity,
    tr.has_moderator_only_tag,
    tr.has_required_tag,
    tr.tag_list_canonical,
    dense_rank() over (order by pf.composite_engagement_score desc NULLS LAST) as rank_by_engagement,
    row_number() over (partition by pf.posttype_name order by pf.creationdate desc) as recency_seq_in_type,
    percent_rank() over (order by coalesce(pf.total_votes_for_ranking, 0)) as pct_by_votes
  from post_features pf
  left join tag_rollup tr on tr.post_id = pf.post_id
),
cohorts as (
  select post_id, 'hot_questions' as cohort
  from ranking
  where posttype_name = 'Question'
    and rank_by_engagement <= 100
  union all
  select post_id, 'new_answers' as cohort
  from ranking
  where posttype_name = 'Answer'
    and recency_seq_in_type <= 200
  union all
  select post_id, 'controversial' as cohort
  from ranking
  where coalesce(downvotes, 0) >= greatest(3, coalesce(upvotes, 0) / 2)
),
final as (
  select
    r.post_id,
    r.posttype_name,
    r.creationdate,
    r.displayname as owner_displayname,
    r.reputation as owner_reputation,
    coalesce(r.location, 'Unknown') as owner_location,
    r.user_recent_posts,
    r.user_last_post_at,
    r.upvotes,
    r.downvotes,
    r.favorites,
    r.total_votes,
    r.comments_total,
    r.close_events,
    r.duplicate_links,
    r.related_links,
    r.known_tags,
    r.tag_list_canonical,
    r.sum_tag_popularity,
    r.max_tag_popularity,
    r.rank_by_engagement,
    r.recency_seq_in_type,
    r.pct_by_votes,
    r.composite_engagement_score,
    case when r.close_reason_id is not null then
      coalesce(
        (select crt.name from closereasontypes crt where crt.id = r.close_reason_id),
        'Unknown Reason'
      )
    else null end as close_reason_name,
    case
      when r.total_votes is null or r.total_votes = 0 then 'Unvoted'
      when r.upvotes >= coalesce(r.downvotes, 0) * 3 then 'Well Received'
      when r.downvotes > r.upvotes then 'Poorly Received'
      else 'Mixed'
    end as reception_bucket,
    case
      when r.posttype_name = 'Question' and coalesce(r.known_tags, 0) = 0 then 'Untagged/Unknown'
      when r.posttype_name = 'Question' then 'Tagged'
      else 'N/A'
    end as tag_status,
    case when r.posttype_name = 'Question' then (
      select count(*) from posts a where a.parentid = r.post_id and a.posttypeid = 2
    ) end as live_answer_count,
    case when r.posttype_name = 'Question' then (
      select case when exists (
        select 1 from posts q where q.id = r.post_id and q.acceptedanswerid is not null
      ) then 1 else 0 end
    ) end as has_accepted_answer
  from ranking r
)
select
  f.post_id,
  f.posttype_name,
  f.creationdate,
  f.owner_displayname,
  f.owner_reputation,
  f.owner_location,
  f.user_recent_posts,
  f.user_last_post_at,
  f.upvotes,
  f.downvotes,
  f.favorites,
  f.total_votes,
  f.comments_total,
  f.close_events,
  f.duplicate_links,
  f.related_links,
  f.known_tags,
  f.tag_list_canonical,
  f.sum_tag_popularity,
  f.max_tag_popularity,
  f.rank_by_engagement,
  f.recency_seq_in_type,
  f.pct_by_votes,
  f.composite_engagement_score,
  f.close_reason_name,
  f.reception_bucket,
  f.tag_status,
  f.live_answer_count,
  f.has_accepted_answer,
  aw.answer_id as top_answer_id,
  aw.answer_score as top_answer_score,
  aw.answer_rank_by_score,
  aw.answer_rank_by_time,
  upper(substring(coalesce(f.owner_location, 'unknown') from 1 for 20)) as owner_location_20_upper
from final f
left join answer_windows aw
  on aw.question_id = case when f.posttype_name = 'Question' then f.post_id else null end
 and aw.answer_rank_by_score = 1
where
  (
    (f.posttype_name = 'Question' and coalesce(f.sum_tag_popularity, 0) > 0)
    or (f.posttype_name = 'Answer' and f.total_votes >= 1)
  )
  and coalesce(f.close_events, 0) <= 2
  and (
    f.rank_by_engagement <= 500
    or (f.recency_seq_in_type <= 100 and f.pct_by_votes >= 0.25)
    or exists (
      select 1 from cohorts c
      where c.post_id = f.post_id and c.cohort in ('hot_questions', 'controversial')
    )
  )
order by
  f.posttype_name asc,
  f.rank_by_engagement asc,
  f.creationdate desc
limit 1000;