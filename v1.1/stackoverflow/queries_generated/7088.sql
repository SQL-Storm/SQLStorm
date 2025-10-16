-- {"query": "7088.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1994} 
with
-- recent activity per post including last comment and last history
recent_activity as (
  select
    p.id,
    p.posttypeid,
    p.parentid,
    p.owneruserid,
    p.title,
    p.tags,
    p.score,
    p.viewcount,
    p.creationdate,
    p.lastactivitydate,
    coalesce(max(c.creationdate) filter (where c.id is not null), max(ph.creationdate) filter (where ph.id is not null)) as last_any_activity,
    (select count(*) from comments c2 where c2.postid = p.id) as comment_count_calc,
    (select count(*) from votes v2 where v2.postid = p.id and v2.votetypeid = 2) as upvote_count,
    (select count(*) from votes v2 where v2.postid = p.id and v2.votetypeid = 3) as downvote_count
  from posts p
  left join comments c on c.postid = p.id
  left join posthistory ph on ph.postid = p.id
  group by p.id, p.posttypeid, p.parentid, p.owneruserid, p.title, p.tags, p.score, p.viewcount, p.creationdate, p.lastactivitydate
),
-- explode tags into rows (PostTags)
post_tags as (
  select
    ra.id as postid,
    trim(tag) as tag
  from recent_activity ra
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(ra.tags,'') from 2 for greatest(char_length(coalesce(ra.tags,'')) - 2,0)), '><')) as tag
  ) t
  where ra.tags is not null and ra.tags <> ''
),
-- tag popularity metrics
tag_stats as (
  select
    t.tag,
    count(distinct pt.postid) as questions_with_tag,
    sum(case when ra.posttypeid = 1 then 1 else 0 end) as questions_count,
    sum(case when ra.posttypeid = 2 then 1 else 0 end) as answers_count,
    avg(nullif(ra.score,0)) filter (where ra.score is not null) as avg_score,
    max(ra.viewcount) as max_views
  from post_tags pt
  join posts ra on ra.id = pt.postid
  join lateral (select pt.tag) l on true
  group by t.tag
),
-- users activity windowed and correlated aggregates
user_metrics as (
  select
    u.id as userid,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    count(distinct p.id) filter (where p.posttypeid = 1) over (partition by u.id) as questions_posted,
    count(distinct p.id) filter (where p.posttypeid = 2) over (partition by u.id) as answers_posted,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) over (partition by u.id) as vote_balance,
    row_number() over (partition by u.id order by p.creationdate desc nulls last) as rn_recent_post
  from users u
  left join posts p on p.owneruserid = u.id
  left join votes v on v.userid = u.id
),
-- identify hot questions: combination of recency, score, viewcount, answers and tag diversity
hot_questions as (
  select
    ra.*,
    ts.questions_with_tag,
    coalesce(ra.score,0) * 1.5 + coalesce(ra.viewcount,0)/100.0 + coalesce(ra.comment_count_calc,0)*2.0 + coalesce((select count(*) from posts a where a.parentid = ra.id),0)*3.0 as hotness_score,
    dense_rank() over (order by coalesce(ra.score,0) desc, coalesce(ra.viewcount,0) desc, ra.last_any_activity desc) as hot_rank
  from recent_activity ra
  left join lateral (
    select count(distinct tag) as questions_with_tag
    from post_tags pt2 where pt2.postid = ra.id
  ) ts on true
  where ra.posttypeid = 1
),
-- correlated subquery for duplicate chains depth using recursive CTE
duplicate_chains as (
  select pl.postid, pl.relatedpostid, 1 as depth, array[pl.postid, pl.relatedpostid] as chain
  from postlinks pl
  where pl.linktypeid = 3
  union all
  select dc.postid, pl.relatedpostid, dc.depth + 1, dc.chain || pl.relatedpostid
  from duplicate_chains dc
  join postlinks pl on pl.postid = dc.relatedpostid and pl.linktypeid = 3
  where not pl.relatedpostid = any(dc.chain)
),
dup_summary as (
  select postid, max(depth) as max_dup_depth, count(distinct relatedpostid) as dup_count
  from duplicate_chains
  group by postid
),
-- assemble final rich result set
ranked_posts as (
  select
    ra.id,
    ra.posttypeid,
    ra.title,
    ra.owneruserid,
    coalesce(u.displayname, ra.ownerdisplayname, 'unknown') as owner_name,
    ra.creationdate,
    ra.last_any_activity,
    ra.score,
    ra.viewcount,
    ra.comment_count_calc,
    ra.upvote_count,
    ra.downvote_count,
    coalesce(ds.dup_count,0) as duplicate_count,
    coalesce(ds.max_dup_depth,0) as duplicate_chain_depth,
    hq.hotness_score,
    hq.hot_rank,
    (
      select string_agg(distinct t.tag, ',') from post_tags t where t.postid = ra.id
    ) as tag_list,
    -- complex conditional: health metric
    case
      when ra.posttypeid = 1 and (coalesce(ra.upvote_count,0) - coalesce(ra.downvote_count,0)) > 10 and coalesce(ra.viewcount,0) > 1000 then 'healthy'
      when ra.posttypeid = 1 and (coalesce(ra.upvote_count,0) - coalesce(ra.downvote_count,0)) < 0 then 'controversial'
      when ra.posttypeid = 2 and coalesce(ra.score,0) >= 5 then 'highly-rated-answer'
      else 'normal'
    end as status,
    -- calculated string expression
    left(coalesce(ra.title,'[no title]'), 120) || coalesce(' [' || coalesce((select min(name) from posthistorytypes pht where pht.id = (select ph.posthistorytypeid from posthistory ph where ph.postid = ra.id limit 1)), '') || ']', '') as short_title
  from recent_activity ra
  left join users u on u.id = ra.owneruserid
  left join dup_summary ds on ds.postid = ra.id
  left join hot_questions hq on hq.id = ra.id
)
select
  rp.*,
  ts.questions_with_tag as sample_tag_popularity,
  -- aggregate window: rolling counts of posts by same owner in last 30 days
  sum(case when rp.creationdate >= now() - interval '30 days' then 1 else 0 end) over (partition by rp.owneruserid order by rp.creationdate range between interval '30 days' preceding and current row) as posts_last_30_days,
  -- correlated subquery for accepted answer acceptance lag
  (
    select extract(epoch from (a.creationdate - q.creationdate))/3600.0
    from posts a
    join posts q on q.id = rp.id and q.acceptedanswerid = a.id
    where a.id = q.acceptedanswerid
    limit 1
  ) as hours_to_accept,
  -- existence checks and null logic
  case
    when exists (select 1 from comments c where c.postid = rp.id and c.creationdate > rp.last_any_activity - interval '1 day') then true
    else false
  end as recent_comment_activity,
  -- last 3 editors via correlated subquery concatenated
  (
    select string_agg(distinct coalesce(u2.displayname, ph.userdisplayname, 'anon') || ':' || to_char(ph.creationdate,'YYYY-MM-DD'), '; ')
    from posthistory ph
    left join users u2 on u2.id = ph.userid
    where ph.postid = rp.id
    order by ph.creationdate desc
    limit 3
  ) as recent_editors
from ranked_posts rp
left join tag_stats ts on ts.tag = split_part(coalesce(rp.tag_list,''),',',1)
where
  -- complicated predicate combining nulls, regex, and set membership
  (rp.title is not null and rp.title ~* 'error|exception|fail|unable' )
  or (rp.status = 'hotly-ranked' and rp.hotness_score > 50)
  or (rp.duplicate_count > 0 and rp.duplicate_chain_depth > 1)
order by rp.hot_rank nulls last, rp.hotness_score desc nulls last, rp.creationdate desc
limit 200;