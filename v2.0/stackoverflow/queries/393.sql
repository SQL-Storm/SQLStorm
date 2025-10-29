-- {"query": "393.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3860}
with recent_users as (
  select u.id,
         u.displayname,
         u.reputation,
         u.creationdate,
         coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
         date_trunc('month', u.creationdate) as cohort_month,
         row_number() over (order by u.creationdate desc, u.id desc) as rn_global
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
  select
    u.id as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    count(distinct case when p.posttypeid = 1 then p.id end) as distinct_qs,
    count(distinct case when p.posttypeid = 2 then p.parentid end) as distinct_answered_questions,
    sum(greatest(p.score, 0)) as nonneg_score_sum,
    sum(least(p.score, 0)) as neg_score_sum,
    sum(p.viewcount) as view_sum,
    max(p.lastactivitydate) as last_post_activity,
    avg(nullif(p.commentcount, 0)) as avg_nonzero_commentcount
  from recent_users u
  left join posts p
    on p.owneruserid = u.id
   and p.creationdate >= u.creationdate
  group by u.id
),
vote_aggs as (
  select
    p.owneruserid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_on_posts,
    count(*) filter (where v.votetypeid = 3) as downvotes_on_posts,
    count(*) filter (where v.votetypeid = 1) as accepts_on_posts,
    count(*) filter (where v.votetypeid in (8,9)) as bounty_events,
    sum(coalesce(v.bountyamount,0)) as bounty_amount_total
  from posts p
  left join votes v
    on v.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
badge_aggs as (
  select
    b.userid as user_id,
    count(*) as badge_count,
    count(*) filter (where b.class = 1) as gold_count,
    count(*) filter (where b.class = 2) as silver_count,
    count(*) filter (where b.class = 3) as bronze_count,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date,
    count(*) filter (where b.tagbased = true) as tag_badges
  from badges b
  group by b.userid
),
question_quality as (
  select
    p.owneruserid as user_id,
    percentile_cont(0.5) within group (order by p.score) as q_score_p50,
    percentile_cont(0.9) within group (order by p.score) as q_score_p90,
    avg(p.viewcount) as q_avg_views,
    count(*) filter (where p.acceptedanswerid is not null) as accepted_qs
  from posts p
  where p.posttypeid = 1
  group by p.owneruserid
),
answer_quality as (
  select
    p.owneruserid as user_id,
    percentile_cont(0.5) within group (order by p.score) as a_score_p50,
    percentile_cont(0.9) within group (order by p.score) as a_score_p90,
    count(*) filter (where p.score > 0) as pos_answers,
    count(*) filter (where p.score < 0) as neg_answers
  from posts p
  where p.posttypeid = 2
  group by p.owneruserid
),
edits_cte as (
  select
    ph.userid as user_id,
    count(*) as edits_total,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits_content,
    count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15)) as moderation_events,
    max(ph.creationdate) as last_edit_date
  from posthistory ph
  group by ph.userid
),
closures_cte as (
  select
    p.owneruserid as user_id,
    count(*) filter (where ph.posthistorytypeid = 10) as closed_events,
    count(*) filter (where ph.posthistorytypeid = 11) as reopened_events,
    count(*) filter (where ph.posthistorytypeid in (35,36)) as migrated_events
  from posts p
  join posthistory ph
    on ph.postid = p.id
  group by p.owneruserid
),
dupe_graph as (
  select
    p.owneruserid as user_id,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links_out,
    count(*) filter (where pl.linktypeid = 1) as linked_posts_out
  from posts p
  left join postlinks pl
    on pl.postid = p.id
  group by p.owneruserid
),
tag_signal as (
  select
    p.owneruserid as user_id,
    count(*) as tag_hits,
    count(*) filter (where position('><sql><' in coalesce(p.tags,'')) > 0 or strpos(coalesce(p.tags,''), 'sql') > 0) as sqlish_hits,
    count(*) filter (where position('><python><' in coalesce(p.tags,'')) > 0 or strpos(coalesce(p.tags,''), 'python') > 0) as pythonish_hits,
    max(length(coalesce(p.tags,''))) as max_tag_str_len
  from posts p
  where p.posttypeid = 1
  group by p.owneruserid
),
comment_sentiment as (
  select
    c.userid as user_id,
    count(*) as comments_made,
    sum(c.score) as comment_score_sum,
    avg(c.score) as comment_score_avg,
    sum(case when lower(c.text) like '%thanks%' then 1 else 0 end) as said_thanks,
    sum(case when lower(c.text) like '%sorry%' then 1 else 0 end) as said_sorry
  from comments c
  group by c.userid
),
activity_rank as (
  select
    u.id as user_id,
    dense_rank() over (order by ua.q_count desc nulls last, ua.a_count desc nulls last, u.reputation desc nulls last) as content_rank,
    dense_rank() over (order by coalesce(va.upvotes_on_posts,0) - coalesce(va.downvotes_on_posts,0) desc, u.reputation desc) as vote_impact_rank,
    dense_rank() over (order by coalesce(ba.gold_count,0) desc, coalesce(ba.silver_count,0) desc, coalesce(ba.bronze_count,0) desc) as badge_rank
  from recent_users u
  left join user_activity ua on ua.user_id = u.id
  left join vote_aggs va on va.user_id = u.id
  left join badge_aggs ba on ba.user_id = u.id
),
top_tags as (
  select
    t.tagname,
    t.count,
    row_number() over (order by t.count desc, t.tagname) as rn
  from tags t
),
user_top_tag as (
  select
    p.owneruserid as user_id,
    unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname
  from posts p
  where p.posttypeid = 1
),
user_tag_pref as (
  select
    utt.user_id,
    utt.tagname,
    count(*) as tag_uses,
    row_number() over (partition by utt.user_id order by count(*) desc, utt.tagname) as rn
  from user_top_tag utt
  group by utt.user_id, utt.tagname
),
bench_base as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.cohort_month,
    u.location_norm,
    ua.q_count,
    ua.a_count,
    ua.distinct_qs,
    ua.distinct_answered_questions,
    ua.nonneg_score_sum,
    ua.neg_score_sum,
    ua.view_sum,
    ua.last_post_activity,
    ua.avg_nonzero_commentcount,
    coalesce(va.upvotes_on_posts,0) as upvotes_on_posts,
    coalesce(va.downvotes_on_posts,0) as downvotes_on_posts,
    coalesce(va.accepts_on_posts,0) as accepts_on_posts,
    coalesce(va.bounty_events,0) as bounty_events,
    coalesce(va.bounty_amount_total,0) as bounty_amount_total,
    coalesce(ba.badge_count,0) as badge_count,
    coalesce(ba.gold_count,0) as gold_count,
    coalesce(ba.silver_count,0) as silver_count,
    coalesce(ba.bronze_count,0) as bronze_count,
    ba.first_badge_date,
    ba.last_badge_date,
    coalesce(ba.tag_badges,0) as tag_badges,
    qq.q_score_p50,
    qq.q_score_p90,
    qq.q_avg_views,
    qq.accepted_qs,
    aq.a_score_p50,
    aq.a_score_p90,
    aq.pos_answers,
    aq.neg_answers,
    ed.edits_total,
    ed.edits_content,
    ed.moderation_events,
    ed.last_edit_date,
    cl.closed_events,
    cl.reopened_events,
    cl.migrated_events,
    dg.duplicate_links_out,
    dg.linked_posts_out,
    ts.tag_hits,
    ts.sqlish_hits,
    ts.pythonish_hits,
    ts.max_tag_str_len,
    cs.comments_made,
    cs.comment_score_sum,
    cs.comment_score_avg,
    cs.said_thanks,
    cs.said_sorry,
    ar.content_rank,
    ar.vote_impact_rank,
    ar.badge_rank,
    utp.tagname as top_user_tag
  from recent_users u
  left join user_activity ua on ua.user_id = u.id
  left join vote_aggs va on va.user_id = u.id
  left join badge_aggs ba on ba.user_id = u.id
  left join question_quality qq on qq.user_id = u.id
  left join answer_quality aq on aq.user_id = u.id
  left join edits_cte ed on ed.user_id = u.id
  left join closures_cte cl on cl.user_id = u.id
  left join dupe_graph dg on dg.user_id = u.id
  left join tag_signal ts on ts.user_id = u.id
  left join comment_sentiment cs on cs.user_id = u.id
  left join activity_rank ar on ar.user_id = u.id
  left join user_tag_pref utp on utp.user_id = u.id and utp.rn = 1
),
score_calc as (
  select
    b.*,
    /* composite score blending content, quality, and engagement */
    cast(
    (
      coalesce(q_count,0) * 1.5
      + coalesce(a_count,0) * 2.0
      + coalesce(upvotes_on_posts,0) * 0.8
      - coalesce(downvotes_on_posts,0) * 1.2
      + coalesce(accepts_on_posts,0) * 3.0
      + coalesce(gold_count,0) * 5.0
      + coalesce(silver_count,0) * 2.0
      + coalesce(bronze_count,0) * 1.0
      + least(coalesce(q_score_p90,0), 50) * 0.6
      + least(coalesce(a_score_p90,0), 50) * 0.6
      + coalesce(sqlish_hits,0) * 0.2
      + coalesce(pythonish_hits,0) * 0.2
      + case when coalesce(closed_events,0) > coalesce(reopened_events,0) then -2 else 1 end
      + case when coalesce(edits_total,0) > 0 then 0.5 else 0 end
      + ln(1 + greatest(coalesce(view_sum,0),0)) * 0.3
      + case when coalesce(bounty_amount_total,0) > 0 then 1 else 0 end
    ) as numeric(18,4)
    ) as composite_score
  from bench_base b
),
ranked as (
  select
    s.*,
    ntile(10) over (order by composite_score desc nulls last) as decile,
    row_number() over (order by composite_score desc nulls last, reputation desc nulls last, user_id) as global_rank,
    row_number() over (partition by cohort_month order by composite_score desc nulls last, reputation desc nulls last, user_id) as cohort_rank
  from score_calc s
),
cohort_stats as (
  select
    r.cohort_month,
    count(*) as cohort_size,
    avg(r.composite_score) as cohort_avg_score,
    percentile_cont(0.5) within group (order by r.composite_score) as cohort_p50,
    percentile_cont(0.9) within group (order by r.composite_score) as cohort_p90
  from ranked r
  group by r.cohort_month
),
final_set as (
  select
    r.user_id,
    r.displayname,
    r.reputation,
    r.location_norm,
    r.cohort_month,
    r.q_count,
    r.a_count,
    r.upvotes_on_posts,
    r.downvotes_on_posts,
    r.accepts_on_posts,
    r.badge_count,
    r.gold_count,
    r.silver_count,
    r.bronze_count,
    r.q_score_p90,
    r.a_score_p90,
    r.tag_hits,
    r.sqlish_hits,
    r.pythonish_hits,
    r.duplicate_links_out,
    r.linked_posts_out,
    r.comments_made,
    r.comment_score_avg,
    r.top_user_tag,
    r.composite_score,
    r.decile,
    r.global_rank,
    r.cohort_rank,
    cs.cohort_size,
    cs.cohort_avg_score,
    cs.cohort_p50,
    cs.cohort_p90
  from ranked r
  left join cohort_stats cs
    on cs.cohort_month = r.cohort_month
),
-- deliberately include a set operator to stress planner: users with high score vs. users with high badges
hi_score as (
  select user_id from final_set where composite_score > (select percentile_cont(0.8) within group (order by composite_score) from final_set)
),
hi_badges as (
  select user_id from bench_base where coalesce(gold_count,0) >= 1 or coalesce(silver_count,0) >= 5 or coalesce(badge_count,0) >= 25
),
segmented as (
  select
    f.*,
    case
      when f.user_id in (select user_id from hi_score intersect select user_id from hi_badges) then 'HiScore+HiBadge'
      when f.user_id in (select user_id from hi_score except select user_id from hi_badges) then 'HiScoreOnly'
      when f.user_id in (select user_id from hi_badges except select user_id from hi_score) then 'HiBadgeOnly'
      else 'Other'
    end as segment
  from final_set f
)
select
  s.user_id,
  s.displayname,
  s.location_norm,
  s.reputation,
  s.cohort_month,
  s.q_count,
  s.a_count,
  s.upvotes_on_posts,
  s.downvotes_on_posts,
  s.accepts_on_posts,
  s.badge_count,
  s.gold_count,
  s.silver_count,
  s.bronze_count,
  s.q_score_p90,
  s.a_score_p90,
  s.tag_hits,
  s.sqlish_hits,
  s.pythonish_hits,
  s.duplicate_links_out,
  s.linked_posts_out,
  s.comments_made,
  s.comment_score_avg,
  coalesce(s.top_user_tag, (select tagname from top_tags where rn = 1)) as representative_tag,
  s.composite_score,
  s.decile,
  s.global_rank,
  s.cohort_rank,
  s.cohort_size,
  s.cohort_avg_score,
  s.cohort_p50,
  s.cohort_p90,
  s.segment,
  -- complicated predicate demonstration:
  case
    when s.reputation >= 10000 and coalesce(s.gold_count,0) >= 1 and s.decile <= 2 then 'Elite'
    when s.reputation between 2000 and 9999 and s.decile <= 4 then 'Advanced'
    when s.reputation < 2000 and s.decile <= 6 then 'Rising'
    when s.badge_count is null and s.composite_score is null then 'Uninitialized'
    else 'Active'
  end as tier_label
from segmented s
where
  (
    (s.q_count is not null and s.a_count is not null)
    or (s.comments_made is not null and s.comment_score_avg is not null)
    or (s.badge_count is not null)
  )
  and (
    coalesce(s.sqlish_hits,0) + coalesce(s.pythonish_hits,0) >= 0
    and (s.duplicate_links_out is null or s.duplicate_links_out >= 0)
  )
  and (
    s.displayname is null
    or length(trim(s.displayname)) >= 0
  )
order by s.decile, s.global_rank
limit 500;