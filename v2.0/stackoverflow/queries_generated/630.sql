-- {"query": "630.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 4252} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    date_trunc('month', u.creationdate) as cohort_month,
    coalesce(nullif(btrim(u.location), ''), '(unknown)') as location_norm,
    case when u.websiteurl ilike '%github%' then 1 else 0 end as has_github
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    sum(coalesce(p.score,0)) as total_post_score,
    count(*) filter (where p.closeddate is not null) as closed_q_count,
    max(p.lastactivitydate) as last_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
user_votes as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid = 5) as favorites_cast,
    count(*) filter (where v.votetypeid in (8,9)) as bounties_touched,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_paid
  from votes v
  where v.userid is not null
  group by v.userid
),
user_badges as (
  select
    b.userid as user_id,
    count(*) as badge_count,
    count(*) filter (where b.class = 1) as gold_count,
    count(*) filter (where b.class = 2) as silver_count,
    count(*) filter (where b.class = 3) as bronze_count,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
question_engagement as (
  select
    p.id as post_id,
    p.owneruserid as owner_id,
    p.creationdate,
    p.viewcount,
    p.score,
    p.answercount,
    coalesce(array_length(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><'), 1), 0) as tag_count,
    exists (
      select 1
      from postlinks pl
      where pl.postid = p.id and pl.linktypeid = 3
    ) as is_marked_duplicate
  from posts p
  where p.posttypeid = 1
),
comment_stats as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    avg(coalesce(c.score,0)) as avg_comment_score,
    min(c.creationdate) as first_comment,
    max(c.creationdate) as last_comment
  from comments c
  where c.userid is not null
  group by c.userid
),
post_quality_window as (
  select
    q.owner_id,
    q.post_id,
    q.creationdate,
    q.viewcount,
    q.score,
    q.answercount,
    q.tag_count,
    q.is_marked_duplicate,
    avg(q.score) over (partition by q.owner_id order by q.creationdate rows between 10 preceding and current row) as rolling_score_avg_11,
    sum(case when q.is_marked_duplicate then 1 else 0 end) over (partition by q.owner_id order by q.creationdate rows between unbounded preceding and current row) as dup_cum_count,
    rank() over (partition by q.owner_id order by coalesce(q.viewcount,0) desc nulls last) as view_rank_within_user
  from question_engagement q
),
recent_edits as (
  select
    ph.postid,
    ph.userid as editor_id,
    ph.posthistorytypeid,
    ph.creationdate,
    ph.comment,
    row_number() over (partition by ph.postid order by ph.creationdate desc) as rn_last_edit
  from posthistory ph
  where ph.posthistorytypeid in (4,5,6,24) -- edits and suggested edit applied
),
dup_clusters as (
  select
    pl.relatedpostid as canonical_id,
    count(*) as dup_count,
    min(pl.creationdate) as first_dup_seen,
    max(pl.creationdate) as last_dup_seen
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.relatedpostid
),
top_tags as (
  select
    t.tagname,
    t.count,
    t.ismoderatoronly,
    t.isrequired,
    ntile(10) over (order by t.count desc) as popularity_decile
  from tags t
),
user_top_tag_affinity as (
  select
    p.owneruserid as user_id,
    tt.popularity_decile,
    count(*) as posts_in_decile
  from posts p
  join lateral (
    select unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag
  ) ut on p.posttypeid = 1 and p.tags is not null and p.tags like '<%>'
  join top_tags tt on tt.tagname = ut.tag
  group by p.owneruserid, tt.popularity_decile
),
cohort_perf as (
  select
    ru.cohort_month,
    count(distinct ru.user_id) as cohort_users,
    avg(ua.q_count + ua.a_count) as avg_posts_per_user,
    percentile_cont(0.5) within group (order by coalesce(ua.total_post_score,0)) as median_user_score,
    sum(coalesce(uv.bounty_paid,0)) as total_bounty_paid
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join user_votes uv on uv.user_id = ru.user_id
  group by ru.cohort_month
),
heavy_users as (
  select
    ru.user_id,
    ru.displayname,
    ua.q_count,
    ua.a_count,
    ua.total_post_score,
    coalesce(ua.q_count,0) + coalesce(ua.a_count,0) as total_posts,
    row_number() over (order by coalesce(ua.q_count,0) + coalesce(ua.a_count,0) desc, coalesce(ua.total_post_score,0) desc) as rn
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
),
-- find accepted answerers and cross-check with votes and comments for correlation
answer_accepts as (
  select
    a.owneruserid as user_id,
    count(*) as accepted_answers
  from posts q
  join posts a on a.id = q.acceptedanswerid and a.posttypeid = 2
  where q.posttypeid = 1
  group by a.owneruserid
),
-- synthesize a per-user score combining multiple signals
user_composite as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.location_norm,
    ru.has_github,
    ua.q_count,
    ua.a_count,
    ua.total_post_score,
    cs.comment_count,
    uv.upvotes_cast,
    uv.downvotes_cast,
    uv.favorites_cast,
    uv.bounties_touched,
    uv.bounty_paid,
    ub.badge_count,
    ub.gold_count,
    ub.silver_count,
    ub.bronze_count,
    aa.accepted_answers,
    coalesce(ua.q_count,0) * 1.0
      + coalesce(ua.a_count,0) * 1.2
      + coalesce(ua.total_post_score,0) * 0.8
      + coalesce(ub.gold_count,0) * 10
      + coalesce(ub.silver_count,0) * 4
      + coalesce(ub.bronze_count,0) * 1
      + coalesce(aa.accepted_answers,0) * 3
      - coalesce(uv.downvotes_cast,0) * 0.5
      + least(50, coalesce(cs.comment_count,0)) * 0.1
      + case when ru.has_github = 1 then 2 else 0 end
      as composite_score
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join comment_stats cs on cs.user_id = ru.user_id
  left join user_votes uv on uv.user_id = ru.user_id
  left join user_badges ub on ub.user_id = ru.user_id
  left join answer_accepts aa on aa.user_id = ru.user_id
),
-- generate a synthetic "engagement percentile" per cohort using window functions
user_enrichment as (
  select
    uc.*,
    percent_rank() over (order by coalesce(uc.composite_score,0)) as global_engagement_pr,
    dense_rank() over (order by coalesce(uc.composite_score,0) desc) as global_rank_desc,
    ntile(20) over (order by coalesce(uc.composite_score,0) desc) as global_ventile
  from user_composite uc
),
-- correlate per-user top tag decile skewness
user_tag_skew as (
  select
    uta.user_id,
    max(case when popularity_decile <= 2 then posts_in_decile end) as posts_top_deciles,
    max(case when popularity_decile >= 9 then posts_in_decile end) as posts_bottom_deciles,
    sum(posts_in_decile) as posts_tagged_total
  from user_top_tag_affinity uta
  group by uta.user_id
),
-- normalize some strings and find suspicious emails in AboutMe via correlated subquery
about_me_flags as (
  select
    u.id as user_id,
    (
      select count(*)
      from regexp_matches(coalesce(u.aboutme,''), '([A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,})', 'ig')
    ) as email_mentions,
    (
      select count(*)
      from regexp_matches(coalesce(u.aboutme,''), '(http(s)?://[^\s<>"'']+)', 'ig')
    ) as url_mentions
  from users u
),
final_users as (
  select
    ue.user_id,
    ue.displayname,
    ue.reputation,
    ue.location_norm,
    coalesce(ue.q_count,0) as q_count,
    coalesce(ue.a_count,0) as a_count,
    coalesce(ue.total_post_score,0) as total_post_score,
    coalesce(ue.badge_count,0) as badge_count,
    coalesce(ue.gold_count,0) as gold_count,
    coalesce(ue.silver_count,0) as silver_count,
    coalesce(ue.bronze_count,0) as bronze_count,
    coalesce(ue.accepted_answers,0) as accepted_answers,
    coalesce(ue.upvotes_cast,0) as upvotes_cast,
    coalesce(ue.downvotes_cast,0) as downvotes_cast,
    coalesce(ue.favorites_cast,0) as favorites_cast,
    coalesce(ue.bounty_paid,0) as bounty_paid,
    ue.composite_score,
    ue.global_engagement_pr,
    ue.global_rank_desc,
    ue.global_ventile,
    coalesce(uts.posts_top_deciles,0) as posts_top_tag_deciles,
    coalesce(uts.posts_bottom_deciles,0) as posts_bottom_tag_deciles,
    coalesce(uts.posts_tagged_total,0) as posts_tagged_total,
    coalesce(am.email_mentions,0) as email_mentions_in_about,
    coalesce(am.url_mentions,0) as url_mentions_in_about
  from user_enrichment ue
  left join user_tag_skew uts on uts.user_id = ue.user_id
  left join about_me_flags am on am.user_id = ue.user_id
),
-- build per-post quality aggregates with outer joins to duplicates and edits
post_quality as (
  select
    pqw.owner_id,
    count(*) as questions_count,
    avg(coalesce(pqw.score,0)) as avg_q_score,
    avg(coalesce(pqw.viewcount,0)) as avg_q_views,
    sum(case when pqw.is_marked_duplicate then 1 else 0 end) as dup_marked_count,
    avg(pqw.rolling_score_avg_11) as avg_rolling_score_11,
    avg(case when pqw.view_rank_within_user <= 3 then pqw.viewcount end) as avg_views_top3_per_user
  from post_quality_window pqw
  group by pqw.owner_id
),
-- select recent edits to factor into quality
last_edit_by_post as (
  select
    re.postid,
    re.editor_id,
    re.posthistorytypeid,
    re.creationdate as last_edit_date
  from recent_edits re
  where re.rn_last_edit = 1
),
-- join edits back to questions to compute editor influence
editor_influence as (
  select
    q.owner_id,
    count(*) filter (where le.editor_id = q.owner_id) as self_edits,
    count(*) filter (where le.editor_id is not null and le.editor_id <> q.owner_id) as external_edits
  from question_engagement q
  left join last_edit_by_post le on le.postid = q.post_id
  group by q.owner_id
),
-- combine post and editor aggregates
user_post_profile as (
  select
    pq.owner_id as user_id,
    pq.questions_count,
    pq.avg_q_score,
    pq.avg_q_views,
    pq.dup_marked_count,
    pq.avg_rolling_score_11,
    pq.avg_views_top3_per_user,
    ei.self_edits,
    ei.external_edits
  from post_quality pq
  left join editor_influence ei on ei.owner_id = pq.owner_id
),
-- user suppression flags based on oddities
suppression_flags as (
  select
    fu.user_id,
    case
      when fu.email_mentions_in_about > 3 or fu.url_mentions_in_about > 10 then 1
      when fu.downvotes_cast > fu.upvotes_cast * 2 and fu.reputation < 100 then 1
      else 0
    end as suppress_user
  from final_users fu
),
-- prepare a dense dataset with outer joins to ensure null handling
dense_user as (
  select
    fu.*,
    upp.questions_count,
    upp.avg_q_score,
    upp.avg_q_views,
    upp.dup_marked_count,
    upp.avg_rolling_score_11,
    upp.avg_views_top3_per_user,
    upp.self_edits,
    upp.external_edits,
    sf.suppress_user
  from final_users fu
  left join user_post_profile upp on upp.user_id = fu.user_id
  left join suppression_flags sf on sf.user_id = fu.user_id
),
-- compute global baselines
baselines as (
  select
    avg(coalesce(questions_count,0)) as base_avg_questions,
    avg(coalesce(avg_q_score,0)) as base_avg_q_score,
    avg(coalesce(avg_q_views,0)) as base_avg_q_views
  from dense_user
),
-- correlate against duplication clusters and tag popularity for advanced predicates
dup_and_tag_context as (
  select
    p.owneruserid as user_id,
    count(distinct dc.canonical_id) as canonical_links_touched,
    avg(tt.popularity_decile) as avg_popularity_decile
  from posts p
  left join postlinks pl on pl.postid = p.id and pl.linktypeid in (1,3)
  left join dup_clusters dc on dc.canonical_id = pl.relatedpostid
  left join lateral (
    select unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag
  ) ut on p.posttypeid = 1 and p.tags like '<%>'
  left join top_tags tt on tt.tagname = ut.tag
  where p.owneruserid is not null
  group by p.owneruserid
),
-- produce the final large set for benchmarking with complex expressions and predicates
final as (
  select
    du.user_id,
    coalesce(du.displayname, concat('user#', du.user_id::text)) as displayname,
    du.location_norm,
    du.reputation,
    round(coalesce(du.composite_score,0)::numeric, 2) as composite_score,
    du.global_ventile,
    du.global_rank_desc,
    du.q_count,
    du.a_count,
    du.total_post_score,
    du.badge_count,
    du.gold_count,
    du.silver_count,
    du.bronze_count,
    du.accepted_answers,
    du.upvotes_cast,
    du.downvotes_cast,
    du.favorites_cast,
    du.bounty_paid,
    du.questions_count,
    du.avg_q_score,
    du.avg_q_views,
    du.dup_marked_count,
    du.avg_rolling_score_11,
    du.avg_views_top3_per_user,
    du.self_edits,
    du.external_edits,
    coalesce(dt.canonical_links_touched,0) as canonical_links_touched,
    round(coalesce(dt.avg_popularity_decile,0)::numeric,2) as avg_tag_popularity_decile,
    du.email_mentions_in_about,
    du.url_mentions_in_about,
    du.suppress_user,
    case
      when du.suppress_user = 1 then 'suppress'
      when du.global_ventile <= 2 and coalesce(du.questions_count,0) >= 5 then 'spotlight'
      when du.global_ventile between 3 and 6 then 'elevate'
      else 'normal'
    end as treatment_bucket,
    -- complex predicate-driven flag
    case
      when coalesce(du.avg_q_views,0) > (select base_avg_q_views from baselines) * 2
           and coalesce(du.avg_q_score,0) >= (select base_avg_q_score from baselines)
           and coalesce(du.dup_marked_count,0) = 0
        then 1 else 0 end as breakout_question_author,
    -- string manipulation and null logic
    upper(coalesce(split_part(du.location_norm, ',', 1), 'UNKNOWN')) as region_hint,
    nullif(trim(coalesce(du.displayname,'')), '') is null as is_anon_name
  from dense_user du
  left join dup_and_tag_context dt on dt.user_id = du.user_id
)
select *
from final f
where
  -- complex filter mixing null logic and calculations
  (
    f.suppress_user = 0
    or (f.global_ventile <= 5 and (f.email_mentions_in_about + f.url_mentions_in_about) <= 5)
  )
  and (
    f.q_count + f.a_count >= 1
    or (f.badge_count >= 3 and f.total_post_score is not null)
  )
  and (
    f.avg_tag_popularity_decile is null
    or f.avg_tag_popularity_decile between 3 and 9
  )
  and (
    -- correlate with duplication context or editor influence
    f.canonical_links_touched > 0
    or coalesce(f.external_edits,0) >= coalesce(f.self_edits,0)
    or f.breakout_question_author = 1
  )
order by f.global_rank_desc asc nulls last, f.composite_score desc, f.user_id
limit 500;