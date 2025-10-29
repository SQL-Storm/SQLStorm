-- {"query": "625.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3411} 
with recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    coalesce(p.answercount, 0) as answercount,
    coalesce(p.commentcount, 0) as commentcount,
    p.acceptedanswerid,
    p.closeddate,
    p.communityowneddate
  from posts p
  where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
user_activity as (
  select
    u.id as userid,
    u.displayname,
    u.reputation,
    u.creationdate as usercreationdate,
    u.location,
    coalesce(u.upvotes, 0) as upvotes,
    coalesce(u.downvotes, 0) as downvotes,
    coalesce(u.views, 0) as profileviews,
    count(distinct b.id) filter (where b.class = 1) as gold_badges,
    count(distinct b.id) filter (where b.class = 2) as silver_badges,
    count(distinct b.id) filter (where b.class = 3) as bronze_badges,
    count(*) filter (where b.tagbased = 1) as tag_badges,
    count(*) filter (where b.tagbased = 0) as named_badges,
    max(b.date) as last_badge_date
  from users u
  left join badges b on b.userid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.upvotes, u.downvotes, u.views
),
post_stats as (
  select
    rp.id as postid,
    rp.posttypeid,
    rp.owneruserid,
    rp.creationdate,
    rp.score,
    rp.viewcount,
    rp.title,
    rp.tags,
    rp.answercount,
    rp.commentcount,
    rp.acceptedanswerid,
    rp.closeddate,
    rp.communityowneddate,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount, 0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount, 0) else 0 end) as bounty_awarded,
    count(*) filter (where v.votetypeid in (10,11,12)) as mod_delete_actions
  from recent_posts rp
  left join votes v on v.postid = rp.id
  group by rp.id, rp.posttypeid, rp.owneruserid, rp.creationdate, rp.score, rp.viewcount, rp.title, rp.tags, rp.answercount, rp.commentcount, rp.acceptedanswerid, rp.closeddate, rp.communityowneddate
),
comment_stats as (
  select
    rp.id as postid,
    count(c.id) as comments,
    sum(case when c.score > 0 then 1 else 0 end) as pos_comments,
    max(c.creationdate) as last_comment_date
  from recent_posts rp
  left join comments c on c.postid = rp.id
  group by rp.id
),
linkage as (
  select
    rp.id as postid,
    count(pl.id) filter (where pl.linktypeid = 1) as linked_count,
    count(pl.id) filter (where pl.linktypeid = 3) as dup_count,
    count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as distinct_dup_targets
  from recent_posts rp
  left join postlinks pl on pl.postid = rp.id
  group by rp.id
),
edit_events as (
  select
    rp.id as postid,
    sum(case when ph.posthistorytypeid in (4,5,6,7,8,9,24) then 1 else 0 end) as edit_events,
    sum(case when ph.posthistorytypeid in (10) then 1 else 0 end) as close_votes_events,
    sum(case when ph.posthistorytypeid in (11) then 1 else 0 end) as reopen_events,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as last_edit_date,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (10)) as last_close_event_date
  from recent_posts rp
  left join posthistory ph on ph.postid = rp.id
  group by rp.id
),
question_answer_join as (
  select
    q.id as questionid,
    a.id as answerid,
    a.owneruserid as answererid,
    a.creationdate as answerdate,
    a.score as answerscore
  from posts q
  join posts a on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
    and q.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
answer_ranks as (
  select
    questionid,
    answerid,
    answererid,
    answerscore,
    row_number() over (partition by questionid order by answerscore desc nulls last, answerid) as answer_rank_by_score,
    dense_rank() over (partition by questionid order by coalesce(answerscore, -2147483648) desc) as dr_score
  from question_answer_join
),
tag_expansion as (
  select
    p.id as postid,
    unnest(string_to_array(substring(p.tags, 2, greatest(0, length(p.tags)-2)), '><')) as tagname
  from recent_posts p
  where p.tags is not null and p.posttypeid = 1
),
top_tags as (
  select
    te.tagname,
    count(*) as cnt,
    percentile_cont(0.5) within group (order by ps.score) as median_score
  from tag_expansion te
  join post_stats ps on ps.postid = te.postid
  group by te.tagname
  having count(*) >= 5
),
user_post_agg as (
  select
    ps.owneruserid as userid,
    count(*) as posts_total,
    count(*) filter (where ps.posttypeid = 1) as questions_total,
    count(*) filter (where ps.posttypeid = 2) as answers_total,
    sum(coalesce(ps.viewcount,0)) as views_total,
    sum(coalesce(ps.upvotes,0)) as upvotes_total,
    sum(coalesce(ps.downvotes,0)) as downvotes_total,
    sum(coalesce(ps.favorites,0)) as favorites_total,
    avg(ps.score) as avg_post_score,
    max(ps.creationdate) as last_post_date
  from post_stats ps
  group by ps.owneruserid
),
quality_score as (
  select
    ps.postid,
    ps.owneruserid,
    (coalesce(ps.upvotes,0) - coalesce(ps.downvotes,0)) * 1.0
      + coalesce(ps.favorites,0) * 0.5
      + case when ps.posttypeid = 1 then coalesce(ps.viewcount,0) * 0.001 else 0 end
      + case when ps.acceptedanswerid is not null then 5 else 0 end
      - case when ps.closeddate is not null then 10 else 0 end
      + least(10, coalesce(cs.comments,0)) * 0.2
      + greatest(0, coalesce(lk.linked_count,0) - coalesce(lk.dup_count,0)) * 0.3
      + coalesce(ed.edit_events,0) * 0.1
    as quality_score
  from post_stats ps
  left join comment_stats cs on cs.postid = ps.postid
  left join linkage lk on lk.postid = ps.postid
  left join edit_events ed on ed.postid = ps.postid
),
user_quality as (
  select
    qa.userid,
    avg(qs.quality_score) as avg_quality_score,
    percentile_cont(0.9) within group (order by qs.quality_score) as p90_quality,
    sum(case when qs.quality_score >= 10 then 1 else 0 end) as high_quality_posts,
    sum(case when qs.quality_score < 0 then 1 else 0 end) as low_quality_posts
  from quality_score qs
  join post_stats qa on qa.postid = qs.postid
  group by qa.userid
),
dupe_clusters as (
  select
    rp.id as postid,
    count(*) filter (where pl.linktypeid = 3) as dupe_links_out,
    count(*) filter (where inv.linktypeid = 3) as dupe_links_in
  from recent_posts rp
  left join postlinks pl on pl.postid = rp.id
  left join postlinks inv on inv.relatedpostid = rp.id and inv.linktypeid = 3
  group by rp.id
),
activity_timeline as (
  select
    ps.postid,
    ps.creationdate::date as day,
    count(*) over (partition by ps.owneruserid, ps.creationdate::date) as posts_that_day_by_user
  from post_stats ps
),
post_flags as (
  select
    ps.postid,
    case when ps.posttypeid = 1 and ps.answercount = 0 and now() - ps.creationdate > interval '30 days' then 1 else 0 end as stale_unanswered_flag,
    case when ps.posttypeid = 1 and ps.acceptedanswerid is not null and ps.score < 0 then 1 else 0 end as accepted_but_negative_flag,
    case when ps.posttypeid = 2 and ps.score >= 10 and ps.creationdate >= now() - interval '7 days' then 1 else 0 end as hot_new_answer_flag
  from post_stats ps
),
accepted_answer_info as (
  select
    q.id as questionid,
    q.acceptedanswerid,
    a.owneruserid as accepted_owner,
    a.score as accepted_score
  from posts q
  left join posts a on a.id = q.acceptedanswerid
  where q.posttypeid = 1
    and q.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
owner_rank as (
  select
    ps.postid,
    ps.owneruserid,
    rank() over (order by coalesce(ua.reputation,0) desc, ps.owneruserid) as owner_global_reputation_rank
  from post_stats ps
  left join user_activity ua on ua.userid = ps.owneruserid
),
final as (
  select
    ps.postid,
    ps.posttypeid,
    ps.creationdate,
    ps.title,
    substring(coalesce(ps.title,''), 1, 100) as title_snippet,
    ps.owneruserid,
    ua.displayname,
    ua.reputation,
    ua.location,
    ua.gold_badges,
    ua.silver_badges,
    ua.bronze_badges,
    upa.posts_total,
    upa.questions_total,
    upa.answers_total,
    upa.views_total,
    upa.upvotes_total,
    upa.downvotes_total,
    upa.favorites_total,
    upa.avg_post_score,
    uq.avg_quality_score,
    uq.p90_quality,
    uq.high_quality_posts,
    uq.low_quality_posts,
    ps.score,
    ps.viewcount,
    ps.upvotes,
    ps.downvotes,
    ps.favorites,
    ps.bounty_started,
    ps.bounty_awarded,
    ps.mod_delete_actions,
    cs.comments,
    cs.pos_comments,
    cs.last_comment_date,
    lk.linked_count,
    lk.dup_count,
    lk.distinct_dup_targets,
    ed.edit_events,
    ed.close_votes_events,
    ed.reopen_events,
    ed.last_edit_date,
    dc.dupe_links_out,
    dc.dupe_links_in,
    aa.acceptedanswerid,
    aa.accepted_owner,
    aa.accepted_score,
    ar.answer_rank_by_score,
    oq.quality_score,
    pf.stale_unanswered_flag,
    pf.accepted_but_negative_flag,
    pf.hot_new_answer_flag,
    ork.owner_global_reputation_rank,
    tt.tagname as sample_tag,
    tt.cnt as sample_tag_count,
    tt.median_score as sample_tag_median_score,
    at.posts_that_day_by_user,
    case
      when ps.closeddate is not null then 'closed'
      when ps.communityowneddate is not null then 'community'
      when ps.score < 0 then 'negative'
      when ps.score = 0 then 'neutral'
      else 'positive'
    end as post_status_bucket
  from post_stats ps
  left join user_activity ua on ua.userid = ps.owneruserid
  left join user_post_agg upa on upa.userid = ps.owneruserid
  left join user_quality uq on uq.userid = ps.owneruserid
  left join comment_stats cs on cs.postid = ps.postid
  left join linkage lk on lk.postid = ps.postid
  left join edit_events ed on ed.postid = ps.postid
  left join dupe_clusters dc on dc.postid = ps.postid
  left join accepted_answer_info aa on aa.questionid = ps.postid
  left join answer_ranks ar on ar.answerid = ps.acceptedanswerid
  left join quality_score oq on oq.postid = ps.postid
  left join post_flags pf on pf.postid = ps.postid
  left join owner_rank ork on ork.postid = ps.postid
  left join lateral (
    select tt.*
    from top_tags tt
    where tt.tagname in (
      select te.tagname from tag_expansion te where te.postid = ps.postid
    )
    order by tt.cnt desc, tt.tagname
    limit 1
  ) tt on true
  left join activity_timeline at on at.postid = ps.postid
  where coalesce(ps.viewcount,0) >= 0
),
ranked as (
  select
    f.*,
    row_number() over (order by coalesce(f.quality_score, -1e9) desc, f.viewcount desc nulls last, f.postid) as rn,
    ntile(20) over (order by coalesce(f.quality_score, -1e9)) as quality_ventile,
    sum(case when f.acceptedanswerid is not null then 1 else 0 end) over (partition by f.owneruserid) as accepted_count_by_owner
  from final f
)
select *
from ranked
where
  -- complex predicate combining string, null, and numeric logic
  (
    coalesce(position('sql' in lower(coalesce(title,''))), 0) > 0
    or coalesce(sample_tag,'') in ('sql','postgresql','tsql')
    or (posttypeid = 2 and hot_new_answer_flag = 1)
  )
  and (
    (quality_ventile between 1 and 5 and score <= 0)
    or (quality_ventile between 6 and 20 and score >= 0)
  )
  and (
    (acceptedanswerid is null and coalesce(answer_rank_by_score, 0) = 0)
    or (acceptedanswerid is not null and coalesce(accepted_score, -9999) >= -5)
  )
  and not (
    dup_count > 3 and distinct_dup_targets = 0
  )
order by rn
limit 500;