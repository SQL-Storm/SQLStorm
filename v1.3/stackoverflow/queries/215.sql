with
question_tags as (
  select
    p.id as question_id,
    lower(trim(t.tag)) as tag
  from posts p
  cross join lateral (
    select unnest(string_to_array(substring(p.tags,2, length(p.tags)-2), '><')) as tag
  ) t
  where p.posttypeid = 1 and p.tags is not null
),
user_stats as (
  select
    u.id,
    u.displayname,
    u.reputation,
    coalesce(sum(case when p.posttypeid = 1 then 1 else 0 end),0) as questions_posted,
    coalesce(sum(case when p.posttypeid = 2 then 1 else 0 end),0) as answers_posted,
    coalesce(count(b.id),0) as badges_total,
    coalesce(sum(case when b.class = 1 then 1 else 0 end),0) as gold_badges,
    coalesce(sum(case when b.class = 2 then 1 else 0 end),0) as silver_badges,
    coalesce(sum(case when b.class = 3 then 1 else 0 end),0) as bronze_badges,
    max(u.lastaccessdate) over () as global_last_access,
    rank() over (order by coalesce(sum(case when p.posttypeid in (1,2) then 1 else 0 end),0) desc) as activity_rank
  from users u
  left join posts p on p.owneruserid = u.id
  left join badges b on b.userid = u.id
  group by u.id, u.displayname, u.reputation
),
answer_ranks as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.creationdate,
    a.score,
    a.owneruserid,
    row_number() over (partition by a.parentid order by a.score desc NULLS LAST, a.creationdate asc) as answer_rank_by_score,
    dense_rank() over (partition by a.parentid order by a.score desc NULLS LAST) as answer_dense_rank
  from posts a
  where a.posttypeid = 2
),
answer_stats as (
  select
    q.id as question_id,
    count(a.id) as answer_count,
    coalesce(avg(a.score),0) as avg_answer_score,
    coalesce(max(a.score),0) as max_answer_score,
    coalesce(min(a.score),0) as min_answer_score,
    case when count(a.id) > 0 then
      percentile_cont(0.5) within group (order by a.score)
    else null end as median_answer_score,
    count(distinct a.owneruserid) filter (where a.owneruserid is not null) as distinct_answerers
  from posts q
  left join posts a on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
  group by q.id
),
latest_history as (
  select distinct on (ph.postid)
    ph.postid,
    ph.id as history_id,
    ph.posthistorytypeid,
    ph.creationdate as history_date,
    left(coalesce(ph.comment, ph.text, ''), 240) as history_excerpt
  from posthistory ph
  order by ph.postid, ph.creationdate desc NULLS LAST, ph.id desc
),
duplicate_links as (
  select pl.postid, pl.relatedpostid, pl.linktypeid
  from postlinks pl
  where pl.linktypeid = 3
),
hot_signals as (
  select id as postid, viewcount, answercount, commentcount, lastactivitydate from posts
  where posttypeid = 1
    and (
      (viewcount is not null and viewcount > 20000)
      or (answercount is not null and answercount > 20)
      or (commentcount is not null and commentcount > 50)
    )
  union
  select id as postid, viewcount, answercount, commentcount, lastactivitydate from posts
  where posttypeid = 1 and lastactivitydate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days'
  except
  select id as postid, viewcount, answercount, commentcount, lastactivitydate from posts
  where closeddate is not null
),
vote_heat as (
  select
    p.id as postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid in (4,12,16) then 1 else 0 end) as flagged_votes,
    count(v.id) as total_votes,
    case when count(v.id) = 0 then 0.0 else (sum(case when v.votetypeid = 2 then 1 else 0 end) - sum(case when v.votetypeid = 3 then 1 else 0 end)) * 1.0 / nullif(count(v.id),0) end as sentiment
  from posts p
  left join votes v on v.postid = p.id
  group by p.id
),
top_answers as (
  select ar.question_id, ar.answer_id, ar.score, ar.creationdate, ar.owneruserid
  from answer_ranks ar
  where ar.answer_rank_by_score = 1
),
candidates as (
  select
    q.id as question_id,
    q.title,
    q.creationdate,
    q.owneruserid,
    coalesce(u.displayname, 'anonymous') as owner_name,
    q.score as question_score,
    q.viewcount,
    q.answercount,
    as_agg.answer_count,
    as_agg.avg_answer_score,
    as_agg.max_answer_score,
    as_agg.min_answer_score,
    as_agg.median_answer_score,
    as_agg.distinct_answerers,
    ta.answer_id as top_answer_id,
    ta.score as top_answer_score,
    case when q.acceptedanswerid is not null then
      extract(epoch from ((select a.creationdate from posts a where a.id = q.acceptedanswerid) - q.creationdate))
    else null end as seconds_to_accepted,
    dl.relatedpostid as duplicate_of_postid,
    (select string_agg(distinct qt.tag, ',') from question_tags qt where qt.question_id = q.id) as tag_list,
    lh.history_excerpt as recent_edit_excerpt,
    vh.upvotes,
    vh.downvotes,
    vh.flagged_votes,
    vh.total_votes,
    vh.sentiment,
    case when coalesce(u.reputation,0) = 0 then null else (coalesce((select count(*) from badges b where b.userid = u.id),0) * 1.0 / nullif(u.reputation,0) * 1000) end as badges_per_1000_rep,
    (select count(distinct c.userid) from comments c where c.postid = q.id and c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days' and c.userid is not null) as recent_commenters_90d,
    exists (select 1 from posts a where a.parentid = q.id and a.posttypeid = 2 and a.owneruserid in (select id from users where reputation > 10000)) as has_highrep_answerer,
    (
      coalesce(q.score,0) * 1.5
      + coalesce(as_agg.answer_count,0) * 2.0
      + coalesce(vh.upvotes,0) * 0.75
      - coalesce(vh.downvotes,0) * 1.25
      + coalesce(as_agg.median_answer_score,0) * 1.8
      + (case when ta.score is null then -2 else ta.score end) * 1.2
      + case when q.acceptedanswerid is not null then 10 else 0 end
      + case when exists (select 1 from duplicate_links d where d.postid = q.id) then -15 else 0 end
      + coalesce((select count(*) from comments c where c.postid = q.id),0) * 0.2
      - (case when q.closeddate is not null then 1 else 0 end) * 50
    ) as composite_score
  from posts q
  left join users u on u.id = q.owneruserid
  left join answer_stats as_agg on as_agg.question_id = q.id
  left join top_answers ta on ta.question_id = q.id
  left join latest_history lh on lh.postid = q.id
  left join duplicate_links dl on dl.postid = q.id
  left join vote_heat vh on vh.postid = q.id
  where q.posttypeid = 1
),
final_candidates as (
  select c.*
  from candidates c
  where c.question_id in (select postid from hot_signals)
  union
  select c2.*
  from candidates c2
  where c2.composite_score > 25
  except
  select c3.*
  from candidates c3
  where c3.viewcount < 100 and c3.answercount < 2
),
ranked_final as (
  select
    fc.*,
    row_number() over (
      order by fc.composite_score desc NULLS LAST,
               fc.viewcount desc NULLS LAST,
               fc.answer_count desc NULLS LAST,
               fc.median_answer_score desc NULLS LAST,
               fc.recent_commenters_90d desc NULLS LAST
    ) as rn
  from final_candidates fc
)

select
  rf.rn,
  rf.question_id,
  left(coalesce(rf.title,'(no title)'),200) as title_snippet,
  rf.owner_name,
  rf.tag_list,
  rf.answer_count,
  rf.distinct_answerers,
  rf.top_answer_id,
  rf.top_answer_score,
  rf.median_answer_score,
  rf.seconds_to_accepted,
  rf.duplicate_of_postid,
  rf.recent_edit_excerpt,
  rf.recent_commenters_90d,
  rf.has_highrep_answerer,
  rf.upvotes,
  rf.downvotes,
  rf.flagged_votes,
  rf.total_votes,
  round(coalesce(rf.sentiment,0)::numeric,3) as sentiment_score,
  round(coalesce(rf.composite_score,0)::numeric,3) as composite_score,
  concat(
    coalesce(rf.tag_list,'[no-tags]'),
    ' | views=', coalesce(CAST(rf.viewcount AS text),'0'),
    ' | qscore=', coalesce(CAST(rf.question_score AS text),'0'),
    ' | ans=', coalesce(CAST(rf.answer_count AS text),'0')
  ) as short_summary
from ranked_final rf
where rf.rn <= 100
order by rf.composite_score desc NULLS LAST, rf.rn asc;