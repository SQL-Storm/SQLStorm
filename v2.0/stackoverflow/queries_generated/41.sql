-- {"query": "41.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3000} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           coalesce(nullif(trim(split_part(coalesce(u.location,''), ',', 1)), ''), 'Unknown') as country_guess,
           row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
    select
      u.user_id,
      count(distinct p.id) filter (where p.posttypeid in (1,2)) as total_posts,
      count(*) filter (where c.id is not null) as total_comments,
      sum(votes_up) as upvotes_received,
      sum(votes_down) as downvotes_received,
      sum(case when vt.votetypeid = 5 then 1 else 0 end) as favorites_received,
      max(coalesce(p.lastactivitydate, p.creationdate)) as last_post_activity,
      avg(nullif(p.score,0)) as avg_nonzero_score
    from recent_users u
    left join posts p
      on p.owneruserid = u.user_id
    left join lateral (
        select
          p2.id as pid,
          count(*) filter (where v.votetypeid = 2) as votes_up,
          count(*) filter (where v.votetypeid = 3) as votes_down
        from posts p2
        left join votes v on v.postid = p2.id and v.votetypeid in (2,3,5)
        where p2.owneruserid = u.user_id
        group by p2.id
    ) vagg on vagg.pid = p.id
    left join votes vt on vt.postid = p.id and vt.votetypeid in (5)
    left join comments c on c.postid = p.id
    group by u.user_id
),
question_stats as (
    select
      u.user_id,
      count(*) filter (where q.posttypeid = 1) as q_count,
      avg(nullif(q.viewcount,0)) as avg_nonzero_views,
      sum(coalesce(q.answercount,0)) as answers_received,
      count(*) filter (where q.acceptedanswerid is not null) as accepted_count,
      count(distinct case when q.closeddate is not null then q.id end) as closed_count
    from recent_users u
    left join posts q
      on q.owneruserid = u.user_id and q.posttypeid = 1
    group by u.user_id
),
answer_stats as (
    select
      u.user_id,
      count(*) filter (where a.posttypeid = 2) as a_count,
      avg(a.score) as avg_answer_score,
      count(*) filter (where a.score > 0) as positive_answers,
      count(*) filter (where a.score < 0) as negative_answers
    from recent_users u
    left join posts a
      on a.owneruserid = u.user_id and a.posttypeid = 2
    group by u.user_id
),
badge_rollup as (
    select
      b.userid as user_id,
      count(*) as badges_total,
      count(*) filter (where b.class = 1) as gold,
      count(*) filter (where b.class = 2) as silver,
      count(*) filter (where b.class = 3) as bronze,
      count(*) filter (where b.tagbased = 1) as tag_badges,
      min(b.date) as first_badge_date,
      max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
postlink_graph as (
    select
      u.user_id,
      count(*) filter (where pl.linktypeid = 1) as linked_edges,
      count(*) filter (where pl.linktypeid = 3) as duplicate_edges,
      count(distinct pl.relatedpostid) filter (where pl.linktypeid = 1) as distinct_linked_targets,
      count(distinct pl.relatedpostid) filter (where pl.linktypeid = 3) as distinct_dup_targets
    from recent_users u
    left join posts p on p.owneruserid = u.user_id
    left join postlinks pl on pl.postid = p.id
    group by u.user_id
),
tag_exposure as (
    select
      u.user_id,
      lower(trim(t.tagname)) as tagname,
      sum(coalesce(p.viewcount,0)) as views_for_tag,
      count(*) as posts_with_tag
    from recent_users u
    join posts p on p.owneruserid = u.user_id and p.posttypeid = 1 and p.tags is not null
    join lateral unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag(tagname) on true
    left join tags t on t.tagname = tag.tagname
    group by u.user_id, lower(trim(t.tagname))
),
top_tag_per_user as (
    select distinct on (te.user_id)
      te.user_id,
      te.tagname as top_tag,
      te.views_for_tag,
      te.posts_with_tag
    from tag_exposure te
    order by te.user_id, te.views_for_tag desc nulls last, te.posts_with_tag desc, te.tagname
),
edit_activity as (
    select
      u.user_id,
      count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits_made,
      count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20)) as mod_actions_seen,
      count(distinct ph.postid) as distinct_posts_touched,
      max(ph.creationdate) as last_edit_date
    from recent_users u
    left join posthistory ph on ph.userid = u.user_id
    group by u.user_id
),
close_reasons as (
    select
      q.owneruserid as user_id,
      crt.name as reason_name,
      count(*) as reason_count
    from posts q
    join posthistory ph on ph.postid = q.id and ph.posthistorytypeid = 10
    left join closereasontypes crt
      on crt.id = nullif(ph.comment, '')::smallint
    where q.posttypeid = 1 and q.owneruserid is not null
    group by q.owneruserid, crt.name
),
top_close_reason as (
    select distinct on (cr.user_id)
      cr.user_id,
      coalesce(cr.reason_name, 'Unknown') as top_close_reason,
      cr.reason_count
    from close_reasons cr
    order by cr.user_id, cr.reason_count desc nulls last, cr.top_close_reason
),
vote_velocity as (
    select
      p.owneruserid as user_id,
      avg(extract(epoch from (v.creationdate - p.creationdate)) / 3600.0) filter (where v.votetypeid in (2,3)) as avg_hours_to_vote,
      count(*) filter (where v.votetypeid = 2) as up_count,
      count(*) filter (where v.votetypeid = 3) as down_count
    from posts p
    left join votes v on v.postid = p.id and v.votetypeid in (2,3)
    where p.owneruserid is not null
    group by p.owneruserid
),
ranked_users as (
    select
      u.user_id,
      u.displayname,
      u.reputation,
      u.creationdate,
      u.country_guess,
      coalesce(ua.total_posts,0) as total_posts,
      coalesce(ua.total_comments,0) as total_comments,
      coalesce(ua.upvotes_received,0) as upvotes_received,
      coalesce(ua.downvotes_received,0) as downvotes_received,
      coalesce(ua.favorites_received,0) as favorites_received,
      qs.q_count,
      qs.avg_nonzero_views,
      qs.answers_received,
      qs.accepted_count,
      qs.closed_count,
      ast.a_count,
      ast.avg_answer_score,
      ast.positive_answers,
      ast.negative_answers,
      br.badges_total,
      br.gold, br.silver, br.bronze, br.tag_badges,
      br.first_badge_date, br.last_badge_date,
      pg.linked_edges, pg.duplicate_edges, pg.distinct_linked_targets, pg.distinct_dup_targets,
      tt.top_tag, tt.views_for_tag as top_tag_views, tt.posts_with_tag as top_tag_posts,
      ea.edits_made, ea.mod_actions_seen, ea.distinct_posts_touched, ea.last_edit_date,
      coalesce(tcr.top_close_reason, 'Unknown') as top_close_reason,
      vv.avg_hours_to_vote, vv.up_count, vv.down_count,
      -- Composite score with various NULL-safe components and weights
      (
        coalesce(qs.q_count,0) * 1.0
        + coalesce(ast.a_count,0) * 1.2
        + greatest(coalesce(ua.upvotes_received,0) - coalesce(ua.downvotes_received,0), 0) * 0.5
        + coalesce(br.gold,0) * 5
        + coalesce(br.silver,0) * 2
        + coalesce(br.bronze,0) * 1
        + coalesce(pg.linked_edges,0) * 0.2
        + coalesce(ua.favorites_received,0) * 0.3
        + coalesce(ea.edits_made,0) * 0.1
        + case when coalesce(vv.avg_hours_to_vote, 999999) < 12 then 2 else 0 end
        - coalesce(qs.closed_count,0) * 0.5
      ) as composite_score
    from recent_users u
    left join user_activity ua on ua.user_id = u.user_id
    left join question_stats qs on qs.user_id = u.user_id
    left join answer_stats ast on ast.user_id = u.user_id
    left join badge_rollup br on br.user_id = u.user_id
    left join postlink_graph pg on pg.user_id = u.user_id
    left join top_tag_per_user tt on tt.user_id = u.user_id
    left join edit_activity ea on ea.user_id = u.user_id
    left join top_close_reason tcr on tcr.user_id = u.user_id
    left join vote_velocity vv on vv.user_id = u.user_id
),
outliers as (
    select
      r.*,
      avg(r.composite_score) over () as avg_score,
      stddev_pop(r.composite_score) over () as sd_score,
      percentile_cont(0.95) within group (order by r.composite_score) over () as p95_score,
      rank() over (order by r.composite_score desc nulls last) as rank_desc,
      dense_rank() over (order by coalesce(r.upvotes_received,0) - coalesce(r.downvotes_received,0) desc) as net_vote_rank
    from ranked_users r
),
final as (
    select
      o.*,
      case
        when o.composite_score is null then 'Unknown'
        when o.composite_score >= o.p95_score then 'Top 5%'
        when o.composite_score >= o.avg_score + coalesce(o.sd_score,0) then 'Above Average'
        when o.composite_score <= o.avg_score - coalesce(o.sd_score,0) then 'Below Average'
        else 'Average'
      end as perf_bucket,
      case when o.rank_desc <= 10 then 1 else 0 end as is_top10,
      case when o.net_vote_rank <= 25 then 1 else 0 end as is_top25_netvotes
    from outliers o
),
dupe_pairs as (
    select
      q.owneruserid as user_id,
      count(*) as dup_self_links
    from posts q
    join postlinks pl on pl.postid = q.id and pl.linktypeid = 3
    join posts r on r.id = pl.relatedpostid
    where r.owneruserid = q.owneruserid
    group by q.owneruserid
)
select
  f.user_id,
  coalesce(f.displayname, concat('user#', f.user_id::text)) as displayname,
  f.reputation,
  f.country_guess,
  f.total_posts,
  f.total_comments,
  f.upvotes_received,
  f.downvotes_received,
  f.favorites_received,
  f.q_count,
  f.avg_nonzero_views,
  f.answers_received,
  f.accepted_count,
  f.closed_count,
  f.a_count,
  f.avg_answer_score,
  f.positive_answers,
  f.negative_answers,
  f.badges_total, f.gold, f.silver, f.bronze, f.tag_badges,
  f.linked_edges, f.duplicate_edges, f.distinct_linked_targets, f.distinct_dup_targets,
  f.top_tag,
  f.top_tag_views,
  f.top_tag_posts,
  f.edits_made, f.mod_actions_seen, f.distinct_posts_touched,
  f.last_edit_date,
  f.top_close_reason,
  f.avg_hours_to_vote,
  f.up_count as vote_up_events,
  f.down_count as vote_down_events,
  coalesce(dp.dup_self_links, 0) as duplicate_self_links,
  f.composite_score,
  f.perf_bucket,
  f.rank_desc,
  f.net_vote_rank,
  (select count(*) from ranked_users) as population_size
from final f
left join dupe_pairs dp on dp.user_id = f.user_id
where (f.is_top10 = 1 or f.is_top25_netvotes = 1 or f.perf_bucket in ('Top 5%','Above Average'))
  and (f.total_posts + coalesce(f.badges_total,0)) > 0
order by f.perf_bucket asc, f.rank_desc asc
limit 200;