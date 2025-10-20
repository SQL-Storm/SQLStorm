with
recent_posts as (
  select p.*
  from posts p
  where p.creationdate >= cast('2024-10-01' as date) - interval '365 days'
),
question_tags as (
  select q.id as question_id,
         trim(both ' ' from t.tag) as tag
  from posts q
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(q.tags,''), 2, greatest(length(coalesce(q.tags,''))-2,0)), '><')) as tag
  ) t
  where q.posttypeid = 1
    and coalesce(q.tags,'') <> ''
),
user_badges as (
  select b.userid,
         count(case when b.class = 1 then 1 end)      as gold_badges,
         count(case when b.class = 2 then 1 end)      as silver_badges,
         count(case when b.class = 3 then 1 end)      as bronze_badges,
         count(case when b.tagbased = true then 1 end) as tag_based_badges,
         count(*)                                   as total_badges,
         max(b.date)                                as last_badge_date
  from badges b
  group by b.userid
),
user_post_stats as (
  select u.id as userid,
         count(case when p.posttypeid = 1 then 1 end) as questions_count,
         count(case when p.posttypeid = 2 then 1 end) as answers_count,
         sum(case when p.posttypeid in (1,2) then p.score else 0 end) as total_score,
         avg(case when p.posttypeid in (1,2) and p.score <> 0 then p.score end) as avg_nonzero_score,
         min(case when p.posttypeid in (1,2) then p.creationdate end) as first_post_date,
         max(case when p.posttypeid in (1,2) then p.lastactivitydate end) as last_activity
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
user_top_tags as (
  select ut.userid,
         ut.tag,
         ut.qcnt,
         row_number() over (partition by ut.userid order by ut.qcnt desc, ut.tag) as rn
  from (
    select q.owneruserid as userid,
           qt.tag,
           count(*) as qcnt
    from posts q
    join question_tags qt on qt.question_id = q.id
    where q.posttypeid = 1
      and q.owneruserid is not null
    group by q.owneruserid, qt.tag
  ) ut
),
user_top3_tags_pivot as (
  select userid,
         max(case when rn = 1 then tag end) as top_tag_1,
         max(case when rn = 2 then tag end) as top_tag_2,
         max(case when rn = 3 then tag end) as top_tag_3
  from user_top_tags
  where rn <= 3
  group by userid
),
last_comment as (
  select c.userid,
         c.id as comment_id,
         c.postid,
         c.text,
         c.creationdate
  from comments c
  where c.id = (
    select cc.id
    from comments cc
    where cc.userid = c.userid
      and coalesce(nullif(trim(cc.text),''), '') <> ''
    order by cc.creationdate desc
    limit 1
  )
),
user_link_stats as (
  select p.owneruserid as userid,
         count(distinct case when pl.linktypeid = 1 then pl.relatedpostid end) as outlinks_count,
         count(distinct case when pl.linktypeid = 3 then pl.postid end) as duplicates_marked_count
  from posts p
  left join postlinks pl on pl.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
combined as (
  select u.id as userid,
         u.displayname,
         u.reputation,
         u.creationdate as user_created,
         u.lastaccessdate,
         coalesce(ups.questions_count,0)        as questions_count,
         coalesce(ups.answers_count,0)          as answers_count,
         coalesce(ups.total_score,0)            as total_score,
         (select percentile_cont(0.5) within group (order by p.score)
          from posts p where p.owneruserid = u.id and p.posttypeid in (1,2) and p.score is not null) as median_score,
         (select percentile_cont(0.9) within group (order by p.score)
          from posts p where p.owneruserid = u.id and p.posttypeid in (1,2) and p.score is not null) as p90_score,
         coalesce(ub.total_badges,0)            as total_badges,
         coalesce(ub.gold_badges,0)             as gold_badges,
         coalesce(ub.silver_badges,0)           as silver_badges,
         coalesce(ub.bronze_badges,0)           as bronze_badges,
         ut.top_tag_1,
         ut.top_tag_2,
         ut.top_tag_3,
         coalesce(ls.outlinks_count,0)          as outlinks_count,
         coalesce(ls.duplicates_marked_count,0) as duplicates_marked_count,
         lc.text as last_comment_text,
         lc.creationdate as last_comment_date,
         ups.first_post_date,
         ups.last_activity,
         ups.avg_nonzero_score
  from users u
  left join user_post_stats ups on ups.userid = u.id
  left join user_badges ub on ub.userid = u.id
  left join user_top3_tags_pivot ut on ut.userid = u.id
  left join user_link_stats ls on ls.userid = u.id
  left join last_comment lc on lc.userid = u.id
),
scored as (
  select c.*,
         (ln(coalesce(c.reputation,0)+1) * sqrt(coalesce(c.total_badges,0)+1)
          + (coalesce(c.questions_count,0) + 2*coalesce(c.answers_count,0)) / nullif(greatest(coalesce(c.total_score,0),1),1)
         ) as raw_composite,
         greatest(0, extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - coalesce(c.last_comment_date, c.last_activity, c.user_created)))/86400) as days_since_activity
  from combined c
),
top_by_composite as (
  select userid, displayname, raw_composite, days_since_activity,
         dense_rank() over (order by raw_composite desc nulls last) as composite_rank
  from scored
),
top_by_reputation as (
  select id as userid, displayname, reputation,
         dense_rank() over (order by reputation desc nulls last) as rep_rank
  from users
),
candidates as (
  select userid, displayname, cast(raw_composite as numeric) as score, composite_rank as rank_type
  from top_by_composite
  where composite_rank <= 25
  union
  select tbr.userid, tbr.displayname, cast(tbr.reputation as numeric) as score, -rep_rank as rank_type
  from top_by_reputation tbr
  where rep_rank <= 25
)
select s.userid,
       s.displayname,
       s.reputation,
       s.questions_count,
       s.answers_count,
       s.total_score,
       round(coalesce(s.median_score,0),2) as median_score,
       round(coalesce(s.p90_score,0),2) as p90_score,
       s.total_badges,
       s.gold_badges,
       s.silver_badges,
       s.bronze_badges,
       coalesce(s.top_tag_1, '<<none>>') || coalesce(' | ' || s.top_tag_2, '') || coalesce(' | ' || s.top_tag_3, '') as top_tags_concat,
       s.outlinks_count,
       s.duplicates_marked_count,
       case when s.last_comment_text is null then '<no recent comment>' else substr(s.last_comment_text,1,120) end as last_comment_excerpt,
       s.last_comment_date,
       s.user_created,
       s.lastaccessdate,
       s.raw_composite,
       s.days_since_activity,
       dense_rank() over (order by s.raw_composite desc nulls last, s.reputation desc nulls last) as overall_rank
from scored s
join candidates c on c.userid = s.userid
where (
  exists (
    select 1 from posts p2
    where p2.owneruserid = s.userid
      and p2.posttypeid = 2
      and p2.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
      and not (coalesce(p2.score,0) < -5)
  )
  or s.raw_composite >= (
    select percentile_cont(0.95) within group (order by raw_composite) from scored
  )
)
order by overall_rank
limit 100;