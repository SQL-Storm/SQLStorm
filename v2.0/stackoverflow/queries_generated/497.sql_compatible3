with recent_active_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.location,
    u.creationdate,
    u.lastaccessdate,
    coalesce(nullif(trim(u.websiteurl), ''), '(none)') as websiteurl_norm,
    coalesce(u.upvotes, 0) - coalesce(u.downvotes, 0) as net_votes,
    dense_rank() over (order by u.reputation desc, u.id) as rep_rank
  from users u
  where u.creationdate <= cast('2024-10-01 12:34:56' as timestamp)
    and (u.lastaccessdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days' or u.reputation >= 1000)
),
user_badge_rollup as (
  select
    b.userid,
    count(case when b.class = 1 then 1 end) as gold_cnt,
    count(case when b.class = 2 then 1 end) as silver_cnt,
    count(case when b.class = 3 then 1 end) as bronze_cnt,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
user_post_activity as (
  select
    p.owneruserid as user_id,
    count(case when p.posttypeid = 1 then 1 end) as q_count,
    count(case when p.posttypeid = 2 then 1 end) as a_count,
    sum(greatest(coalesce(p.score,0),0)) as nonneg_score_sum,
    sum(case when p.posttypeid = 1 then coalesce(p.viewcount,0) else 0 end) as question_views,
    max(p.lastactivitydate) as last_post_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
user_comment_stats as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    avg(coalesce(c.score,0)) as avg_comment_score,
    max(c.creationdate) as last_comment_date
  from comments c
  where c.userid is not null
  group by c.userid
),
user_vote_stats as (
  select
    v.userid as user_id,
    count(case when v.votetypeid = 2 then 1 end) as upvotes_cast,
    count(case when v.votetypeid = 3 then 1 end) as downvotes_cast,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
    min(v.creationdate) as first_vote_date,
    max(v.creationdate) as last_vote_date
  from votes v
  where v.userid is not null
  group by v.userid
),
accepted_answers as (
  select
    a.owneruserid as user_id,
    count(*) as accepted_count
  from posts q
  join posts a
    on a.id = q.acceptedanswerid
  where a.owneruserid is not null
  group by a.owneruserid
),
tag_expertise as (
  select
    p.owneruserid as user_id,
    lower(tag) as tagname,
    count(*) as tagged_posts,
    sum(coalesce(p.score,0)) as tag_score
  from (
    select p.*, unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag
    from posts p
    where p.posttypeid = 1
      and p.tags is not null
      and p.owneruserid is not null
  ) p
  group by p.owneruserid, lower(tag)
),
top_tag_per_user as (
  select user_id, tagname, tagged_posts, tag_score,
         row_number() over (partition by user_id order by tag_score desc, tagged_posts desc, tagname) as rn
  from tag_expertise
),
link_dup_activity as (
  select
    pl.postid,
    pl.relatedpostid,
    pl.linktypeid,
    case when pl.linktypeid = 3 then 1 else 0 end as is_duplicate
  from postlinks pl
),
question_close_events as (
  select
    ph.postid,
    min(ph.creationdate) as first_close_date,
    count(*) as close_events
  from posthistory ph
  where ph.posthistorytypeid in (10,35)
  group by ph.postid
),
user_quality_score as (
  select
    u.user_id,
    round(
      0.40 * coalesce(upa.nonneg_score_sum,0) +
      0.25 * coalesce(aacc.accepted_count,0) +
      0.10 * coalesce(uvs.upvotes_cast,0) -
      0.05 * coalesce(uvs.downvotes_cast,0) +
      0.15 * coalesce(ubr.gold_cnt,0) * 5 +
      0.08 * coalesce(ubr.silver_cnt,0) * 2 +
      0.04 * coalesce(ubr.bronze_cnt,0) * 1
    , 2) as quality_score
  from recent_active_users u
  left join user_post_activity upa on upa.user_id = u.user_id
  left join accepted_answers aacc on aacc.user_id = u.user_id
  left join user_vote_stats uvs on uvs.user_id = u.user_id
  left join user_badge_rollup ubr on ubr.userid = u.user_id
),
user_last_activity as (
  select
    u.user_id,
    greatest(
      coalesce(upa.last_post_activity, timestamp '1970-01-01 00:00:00'),
      coalesce(ucs.last_comment_date, timestamp '1970-01-01 00:00:00'),
      coalesce(uvs.last_vote_date, timestamp '1970-01-01 00:00:00'),
      u.lastaccessdate
    ) as last_any_activity
  from recent_active_users u
  left join user_post_activity upa on upa.user_id = u.user_id
  left join user_comment_stats ucs on ucs.user_id = u.user_id
  left join user_vote_stats uvs on uvs.user_id = u.user_id
),
questions_summary as (
  select
    p.owneruserid as user_id,
    count(*) as q_total,
    avg(coalesce(p.score,0)) as q_avg_score,
    sum(case when qce.postid is not null then 1 else 0 end) as q_closed_count,
    sum(coalesce(p.viewcount,0)) as q_total_views
  from posts p
  left join question_close_events qce on qce.postid = p.id
  where p.posttypeid = 1 and p.owneruserid is not null
  group by p.owneruserid
),
answers_summary as (
  select
    p.owneruserid as user_id,
    count(*) as a_total,
    avg(coalesce(p.score,0)) as a_avg_score
  from posts p
  where p.posttypeid = 2 and p.owneruserid is not null
  group by p.owneruserid
),
engagement_rank as (
  select
    u.user_id,
    row_number() over (order by coalesce(ups.q_count,0) + coalesce(ups.a_count,0) desc, u.user_id) as activity_rank
  from recent_active_users u
  left join user_post_activity ups on ups.user_id = u.user_id
),
user_string_profile as (
  select
    u.user_id,
    trim(both from regexp_replace(coalesce(u.displayname, 'anon'), '\s+', ' ', 'g')) as clean_displayname,
    regexp_replace(coalesce(u.location, 'unknown'), '\s+', ' ', 'g') as clean_location,
    case
      when u.websiteurl_norm ilike '%stackoverflow%' then 'SO'
      when u.websiteurl_norm ilike '%github%' then 'GH'
      when u.websiteurl_norm = '(none)' then 'NONE'
      else 'OTHER'
    end as site_bucket
  from recent_active_users u
),
user_null_edgecases as (
  select
    u.id as user_id,
    case when u.displayname is null then 1 else 0 end as is_null_displayname,
    case when u.location is null or length(trim(u.location)) = 0 then 1 else 0 end as is_null_or_blank_location
  from users u
),
question_answer_linkage as (
  select
    q.owneruserid as asker_id,
    a.owneruserid as answerer_id,
    count(*) as interactions
  from posts q
  join posts a on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
    and q.owneruserid is not null
    and a.owneruserid is not null
  group by q.owneruserid, a.owneruserid
),
mutual_interactions as (
  select
    least(asker_id, answerer_id) as u1,
    greatest(asker_id, answerer_id) as u2,
    sum(interactions) as total_interactions
  from question_answer_linkage
  group by least(asker_id, answerer_id), greatest(asker_id, answerer_id)
),
user_interaction_strength as (
  select
    iu.user_id,
    coalesce(sum(mi.total_interactions),0) as interaction_strength
  from recent_active_users iu
  left join mutual_interactions mi
    on mi.u1 = iu.user_id or mi.u2 = iu.user_id
  group by iu.user_id
),
ranked_users as (
  select
    u.user_id,
    u.displayname,
    u.reputation,
    u.location,
    u.net_votes,
    coalesce(ups.q_count,0) as q_count,
    coalesce(ups.a_count,0) as a_count,
    coalesce(qs.q_total,0) as q_total,
    coalesce(qs.q_avg_score,0) as q_avg_score,
    coalesce(qs.q_closed_count,0) as q_closed_count,
    coalesce(qs.q_total_views,0) as q_total_views,
    coalesce(asum.a_total,0) as a_total,
    coalesce(asum.a_avg_score,0) as a_avg_score,
    coalesce(ubr.gold_cnt,0) as gold_cnt,
    coalesce(ubr.silver_cnt,0) as silver_cnt,
    coalesce(ubr.bronze_cnt,0) as bronze_cnt,
    coalesce(aacc.accepted_count,0) as accepted_count,
    coalesce(uvs.upvotes_cast,0) as upvotes_cast,
    coalesce(uvs.downvotes_cast,0) as downvotes_cast,
    coalesce(uvs.bounty_total,0) as bounty_total,
    coalesce(ucs.comment_count,0) as comment_count,
    coalesce(uis.interaction_strength,0) as interaction_strength,
    usp.clean_displayname,
    usp.clean_location,
    usp.site_bucket,
    un.is_null_displayname,
    un.is_null_or_blank_location,
    rep_rank,
    er.activity_rank,
    uls.last_any_activity,
    ut.tagname as top_tag,
    ut.tagged_posts as top_tag_posts,
    ut.tag_score as top_tag_score,
    uqs.quality_score
  from recent_active_users u
  left join user_post_activity ups on ups.user_id = u.user_id
  left join questions_summary qs on qs.user_id = u.user_id
  left join answers_summary asum on asum.user_id = u.user_id
  left join user_badge_rollup ubr on ubr.userid = u.user_id
  left join accepted_answers aacc on aacc.user_id = u.user_id
  left join user_vote_stats uvs on uvs.user_id = u.user_id
  left join user_comment_stats ucs on ucs.user_id = u.user_id
  left join engagement_rank er on er.user_id = u.user_id
  left join user_last_activity uls on uls.user_id = u.user_id
  left join top_tag_per_user ut on ut.user_id = u.user_id and ut.rn = 1
  left join user_quality_score uqs on uqs.user_id = u.user_id
  left join user_string_profile usp on usp.user_id = u.user_id
  left join user_null_edgecases un on un.user_id = u.user_id
  left join user_interaction_strength uis on uis.user_id = u.user_id
),
filters as (
  select
    r.user_id,
    r.displayname,
    r.reputation,
    r.location,
    r.net_votes,
    r.q_count,
    r.a_count,
    r.q_total,
    r.q_avg_score,
    r.q_closed_count,
    r.q_total_views,
    r.a_total,
    r.a_avg_score,
    r.gold_cnt,
    r.silver_cnt,
    r.bronze_cnt,
    r.accepted_count,
    r.upvotes_cast,
    r.downvotes_cast,
    r.bounty_total,
    r.comment_count,
    r.interaction_strength,
    r.clean_displayname,
    r.clean_location,
    r.site_bucket,
    r.is_null_displayname,
    r.is_null_or_blank_location,
    r.rep_rank,
    r.activity_rank,
    r.last_any_activity,
    r.top_tag,
    r.top_tag_posts,
    r.top_tag_score,
    r.quality_score,
    (
      (r.reputation >= 1000 or r.gold_cnt >= 1 or r.accepted_count >= 10) and
      (r.q_total + r.a_total) >= 5 and
      (r.q_avg_score + r.a_avg_score) >= -1 and
      (r.site_bucket <> 'NONE' or r.comment_count >= 3) and
      (r.is_null_displayname = 0)
    ) as passes_primary_filter,
    (
      case
        when r.top_tag is null then 0
        when r.top_tag in ('discussion', 'off-topic') then 0
        else 1
      end
    ) as passes_tag_filter
  from ranked_users r
),
scored as (
  select
    f.*,
    coalesce(f.quality_score, 0) as base_quality_score
  from filters f
),
normalized as (
  select
    f.*,
    base_quality_score +
    coalesce((cast(q_total_views as numeric) / nullif(q_total + 1,0)) * 0.01, 0) +
    coalesce((upvotes_cast - downvotes_cast) * 0.05, 0) +
    coalesce(ln(least(1000, greatest(1, q_total + a_total))), 0) as composite_score
  from scored f
),
final_rank_prep as (
  select
    n.*,
    row_number() over (
      order by n.passes_primary_filter desc,
               n.passes_tag_filter desc,
               n.composite_score desc,
               n.rep_rank asc,
               n.user_id asc
    ) as overall_rank
  from normalized n
),
-- compute approximate 90th percentile in a dialect-agnostic way: use ordered values and pick value at rank
p90_calc as (
  select
    max(composite_score) as p90_composite
  from (
    select composite_score,
           row_number() over (order by composite_score) as rn,
           count(*) over () as total_count
    from final_rank_prep
  ) t
  where rn >= ceil(0.9 * total_count)
),
final_rank as (
  select
    fr.*,
    p.p90_composite,
    avg(fr.composite_score) over () as avg_composite
  from final_rank_prep fr
  cross join (select coalesce(p90_composite, 0) as p90_composite from p90_calc) p
)
select
  fr.overall_rank,
  fr.user_id,
  fr.clean_displayname as display_name,
  fr.reputation,
  fr.net_votes,
  fr.q_total,
  fr.a_total,
  fr.accepted_count,
  fr.gold_cnt,
  fr.silver_cnt,
  fr.bronze_cnt,
  fr.top_tag,
  fr.top_tag_posts,
  fr.top_tag_score,
  fr.composite_score,
  case when fr.composite_score >= fr.p90_composite then 'top10%' else 'other' end as composite_bucket,
  fr.last_any_activity,
  fr.clean_location,
  fr.site_bucket,
  fr.passes_primary_filter,
  fr.passes_tag_filter
from final_rank fr
where fr.passes_primary_filter = true
  and (fr.top_tag is not null or fr.activity_rank <= 1000)
order by fr.overall_rank
limit 200;