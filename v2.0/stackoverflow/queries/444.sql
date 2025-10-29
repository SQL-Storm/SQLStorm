with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
    row_number() over (order by u.creationdate desc, u.id desc) as rn
  from users u
  where u.reputation >= 1
),
top_n_users as (
  select *
  from recent_users
  where rn <= 500
),
user_badge_activity as (
  select
    b.userid,
    count(*) as total_badges,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  join top_n_users u on u.user_id = b.userid
  group by b.userid
),
user_post_summaries as (
  select
    p.owneruserid as user_id,
    sum(case when p.posttypeid = 1 then 1 else 0 end) as question_count,
    sum(case when p.posttypeid = 2 then 1 else 0 end) as answer_count,
    sum(coalesce(p.viewcount, 0)) as total_views,
    sum(coalesce(p.score, 0)) as total_score,
    avg(nullif(p.score, 0)) as avg_nonzero_score,
    count(*) filter (where p.closeddate is not null) as closed_posts,
    max(p.creationdate) as last_post_date
  from posts p
  join top_n_users u on u.user_id = p.owneruserid
  group by p.owneruserid
),
question_tag_explode as (
  select
    q.id as question_id,
    q.owneruserid as user_id,
    unnest(string_to_array(substring(q.tags, 2, length(q.tags) - 2), '><')) as tag
  from posts q
  where q.posttypeid = 1
    and q.tags is not null
),
user_top_tags as (
  select
    qte.user_id,
    qte.tag as top_tag,
    count(*) as tag_uses,
    row_number() over (partition by qte.user_id order by count(*) desc, min(qte.question_id)) as tag_rank
  from question_tag_explode qte
  join top_n_users u on u.user_id = qte.user_id
  group by qte.user_id, qte.tag
),
accepted_answerers as (
  select
    a.owneruserid as user_id,
    count(*) as accepted_answers
  from posts q
  join posts a on a.id = q.acceptedanswerid
  join top_n_users u on u.user_id = a.owneruserid
  where q.posttypeid = 1
    and a.posttypeid = 2
  group by a.owneruserid
),
vote_agg as (
  select
    p.owneruserid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_received,
    count(*) filter (where v.votetypeid = 3) as downvotes_received,
    count(*) filter (where v.votetypeid = 5) as favorites_received
  from posts p
  join votes v on v.postid = p.id
  join top_n_users u on u.user_id = p.owneruserid
  group by p.owneruserid
),
comment_agg as (
  select
    p.owneruserid as user_id,
    count(c.id) as comments_on_posts,
    max(c.creationdate) as last_comment_on_posts
  from posts p
  left join comments c on c.postid = p.id
  join top_n_users u on u.user_id = p.owneruserid
  group by p.owneruserid
),
edit_events as (
  select
    ph.postid,
    ph.userid as editor_user_id,
    count(*) filter (
      where ph.posthistorytypeid in (4,5,6,7,8,9,24)
    ) as edit_events_count,
    max(ph.creationdate) as last_edit_date
  from posthistory ph
  where ph.posthistorytypeid in (4,5,6,7,8,9,24,10,11,12,13,14,15,19,20,35,36,37,38)
  group by ph.postid, ph.userid
),
user_edit_agg as (
  select
    coalesce(p.owneruserid, ee.editor_user_id) as user_id,
    sum(ee.edit_events_count) as total_edit_events,
    max(ee.last_edit_date) as last_edit_date
  from edit_events ee
  left join posts p on p.id = ee.postid
  join top_n_users u on u.user_id = coalesce(p.owneruserid, ee.editor_user_id)
  group by coalesce(p.owneruserid, ee.editor_user_id)
),
duplicate_graph as (
  select
    pl.postid,
    pl.relatedpostid,
    pl.creationdate,
    pl.linktypeid
  from postlinks pl
  where pl.linktypeid = 3
),
user_dup_metrics as (
  select
    coalesce(p.owneruserid, p2.owneruserid) as user_id,
    count(*) filter (where dg.postid = p.id) as duplicates_as_source,
    count(*) filter (where dg.relatedpostid = p.id) as duplicates_as_target,
    min(dg.creationdate) as first_dup_date,
    max(dg.creationdate) as last_dup_date
  from duplicate_graph dg
  left join posts p on p.id = dg.postid
  left join posts p2 on p2.id = dg.relatedpostid
  join top_n_users u on u.user_id = coalesce(p.owneruserid, p2.owneruserid)
  group by coalesce(p.owneruserid, p2.owneruserid)
),
user_quality_score as (
  select
    u.user_id,
    0.6 * coalesce(cast(ps.total_score as numeric), 0)
    + 0.2 * coalesce(cast(va.upvotes_received as numeric), 0)
    - 0.3 * coalesce(cast(va.downvotes_received as numeric), 0)
    + 0.5 * coalesce(cast(aa.accepted_answers as numeric), 0)
    + 0.1 * coalesce(cast(ps.total_views as numeric) / nullif(ps.question_count + ps.answer_count, 0), 0)
    - 0.4 * coalesce(cast(udm.duplicates_as_source as numeric), 0)
    + 0.2 * coalesce(cast(udm.duplicates_as_target as numeric), 0)
    + 2.0 * coalesce(cast(uba.gold_badges as numeric), 0)
    + 1.0 * coalesce(cast(uba.silver_badges as numeric), 0)
    + 0.5 * coalesce(cast(uba.bronze_badges as numeric), 0)
    as quality_score
  from top_n_users u
  left join user_post_summaries ps on ps.user_id = u.user_id
  left join vote_agg va on va.user_id = u.user_id
  left join accepted_answerers aa on aa.user_id = u.user_id
  left join user_dup_metrics udm on udm.user_id = u.user_id
  left join user_badge_activity uba on uba.userid = u.user_id
),
activity_density as (
  select
    u.user_id,
    extract(epoch from (coalesce(nullif(ps.last_post_date, u.creationdate), u.creationdate) - u.creationdate)) / 86400.0 as active_days,
    cast((coalesce(ps.question_count,0) + coalesce(ps.answer_count,0)) as numeric)
      / nullif(extract(epoch from (coalesce(nullif(ps.last_post_date, u.creationdate), u.creationdate) - u.creationdate)) / 86400.0, 0) as posts_per_active_day
  from top_n_users u
  left join user_post_summaries ps on ps.user_id = u.user_id
),
string_fun as (
  select
    u.user_id,
    upper(coalesce(u.location, 'UNKNOWN')) as location_upper,
    regexp_replace(coalesce(u.websiteurl, 'N/A'), '^https?://(www\.)?', '', 'i') as site_hostish,
    substring(coalesce(u.displayname, 'user' || cast(u.user_id as text)) from 1 for 20) as short_name
  from top_n_users u
),
null_logic as (
  select
    u.user_id,
    case
      when uba.total_badges is null and ps.question_count is null and ps.answer_count is null then 'LURKER'
      when coalesce(ps.question_count,0) = 0 and coalesce(ps.answer_count,0) > 0 then 'ANSWERER'
      when coalesce(ps.answer_count,0) = 0 and coalesce(ps.question_count,0) > 0 then 'ASKER'
      when coalesce(ps.question_count,0) + coalesce(ps.answer_count,0) > 100 then 'ACTIVE'
      else 'MIXED'
    end as user_archetype
  from top_n_users u
  left join user_badge_activity uba on uba.userid = u.user_id
  left join user_post_summaries ps on ps.user_id = u.user_id
),
recent_hot_questions as (
  select
    q.id,
    q.owneruserid as user_id,
    q.creationdate,
    q.score,
    q.viewcount,
    q.title,
    dense_rank() over (order by q.score desc, q.viewcount desc, q.creationdate desc) as hot_rank
  from posts q
  where q.posttypeid = 1
    and q.creationdate > cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    and coalesce(q.score,0) >= 0
),
user_recent_hot as (
  select
    u.user_id,
    count(*) filter (where rhq.hot_rank <= 1000) as hot_qs_last3y,
    max(rhq.score) as max_hot_score
  from top_n_users u
  left join recent_hot_questions rhq on rhq.user_id = u.user_id
  group by u.user_id
),
user_recent_commenter as (
  select
    u.user_id,
    count(*) as comments_made_last_year
  from top_n_users u
  left join comments c on c.userid = u.user_id
    and c.creationdate > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
  group by u.user_id
),
ranked as (
  select
    u.user_id,
    u.displayname,
    u.reputation,
    coalesce(ps.question_count,0) as questions,
    coalesce(ps.answer_count,0) as answers,
    coalesce(aa.accepted_answers,0) as accepted_answers,
    coalesce(va.upvotes_received,0) as upvotes_received,
    coalesce(va.downvotes_received,0) as downvotes_received,
    coalesce(va.favorites_received,0) as favorites_received,
    coalesce(uba.total_badges,0) as total_badges,
    coalesce(uba.gold_badges,0) as gold_badges,
    coalesce(uba.silver_badges,0) as silver_badges,
    coalesce(uba.bronze_badges,0) as bronze_badges,
    coalesce(udm.duplicates_as_source,0) as duplicates_as_source,
    coalesce(udm.duplicates_as_target,0) as duplicates_as_target,
    coalesce(uea.total_edit_events,0) as total_edit_events,
    uqs.quality_score,
    ad.posts_per_active_day,
    sf.location_upper,
    sf.site_hostish,
    sf.short_name,
    nl.user_archetype,
    urh.hot_qs_last3y,
    urh.max_hot_score,
    urc.comments_made_last_year,
    row_number() over (
      order by
        uqs.quality_score desc nulls last,
        u.reputation desc,
        coalesce(ps.answer_count,0) desc,
        coalesce(ps.question_count,0) desc,
        u.user_id asc
    ) as overall_rank
  from top_n_users u
  left join user_post_summaries ps on ps.user_id = u.user_id
  left join accepted_answerers aa on aa.user_id = u.user_id
  left join vote_agg va on va.user_id = u.user_id
  left join user_badge_activity uba on uba.userid = u.user_id
  left join user_dup_metrics udm on udm.user_id = u.user_id
  left join user_edit_agg uea on uea.user_id = u.user_id
  left join user_quality_score uqs on uqs.user_id = u.user_id
  left join activity_density ad on ad.user_id = u.user_id
  left join string_fun sf on sf.user_id = u.user_id
  left join null_logic nl on nl.user_id = u.user_id
  left join user_recent_hot urh on urh.user_id = u.user_id
  left join user_recent_commenter urc on urc.user_id = u.user_id
),
dup_explanations as (
  select
    u.user_id,
    string_agg(
      case
        when udm.duplicates_as_source > 0 then 'src:'||cast(udm.duplicates_as_source as text)
        else null
      end
      || case
        when udm.duplicates_as_target > 0 then '|tgt:'||cast(udm.duplicates_as_target as text)
        else null
      end,
      ','
      order by udm.duplicates_as_source desc, udm.duplicates_as_target desc
    ) as dup_summary
  from ranked u
  left join user_dup_metrics udm on udm.user_id = u.user_id
  group by u.user_id
),
final as (
  select
    r.*,
    dt.dup_summary,
    ttags.top_tag,
    ttags.tag_uses,
    row_number() over (partition by r.user_id order by coalesce(ttags.tag_uses,0) desc nulls last, r.overall_rank) as tag_rownum
  from ranked r
  left join user_top_tags ttags on ttags.user_id = r.user_id and ttags.tag_rank <= 3
  left join dup_explanations dt on dt.user_id = r.user_id
)
select
  f.overall_rank,
  f.user_id,
  f.displayname,
  f.reputation,
  f.questions,
  f.answers,
  f.accepted_answers,
  f.upvotes_received,
  f.downvotes_received,
  f.favorites_received,
  f.total_badges,
  f.gold_badges,
  f.silver_badges,
  f.bronze_badges,
  f.total_edit_events,
  f.duplicates_as_source,
  f.duplicates_as_target,
  coalesce(f.dup_summary, 'none') as dup_summary,
  coalesce(f.top_tag, '(none)') as top_tag,
  coalesce(f.tag_uses, 0) as tag_uses,
  round(coalesce(f.quality_score, 0), 2) as quality_score,
  round(coalesce(f.posts_per_active_day, 0), 3) as posts_per_active_day,
  f.location_upper,
  f.site_hostish,
  f.short_name,
  f.user_archetype,
  f.hot_qs_last3y,
  f.max_hot_score
from final f
where f.tag_rownum = 1
order by f.overall_rank
limit 200;