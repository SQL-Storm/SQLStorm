-- {"query": "38066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2060} 
with recent_questions as (
  select p.Id as QuestionId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.OwnerUserId,
         p.Tags,
         p.AcceptedAnswerId
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
tag_expanded as (
  select q.QuestionId,
         unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as tag,
         q.CreationDate,
         q.Score,
         q.ViewCount,
         q.OwnerUserId,
         q.AcceptedAnswerId
  from recent_questions q
  where q.Tags is not null and q.Tags <> ''
),
question_activity as (
  select q.QuestionId,
         count(distinct c.Id) as comment_count,
         coalesce(sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end),0) as net_votes,
         count(distinct case when v.VoteTypeId = 5 then v.UserId end) as unique_favoriters
  from recent_questions q
  left join Comments c on c.PostId = q.QuestionId
  left join Votes v on v.PostId = q.QuestionId
  group by q.QuestionId
),
answer_stats as (
  select a.ParentId as QuestionId,
         count(*) as answer_count,
         max(a.Score) as max_answer_score,
         sum(case when a.Score > 0 then 1 else 0 end) as positive_answers,
         sum(case when a.OwnerUserId is not null then 1 else 0 end) as answered_by_registered
  from Posts a
  where a.PostTypeId = 2
    and a.ParentId in (select QuestionId from recent_questions)
  group by a.ParentId
),
accepted_answerer_rep as (
  select q.QuestionId,
         u.Reputation as accepted_answerer_rep
  from recent_questions q
  join Posts aa on aa.Id = q.AcceptedAnswerId
  left join Users u on u.Id = aa.OwnerUserId
),
question_owner as (
  select q.QuestionId,
         u.Reputation as asker_rep,
         u.UpVotes as asker_upvotes,
         u.DownVotes as asker_downvotes,
         u.CreationDate as user_created
  from recent_questions q
  left join Users u on u.Id = q.OwnerUserId
),
tag_popularity as (
  select te.tag,
         count(distinct te.QuestionId) as tag_q_count,
         sum(te.Score) as tag_total_score,
         sum(te.ViewCount) as tag_total_views
  from tag_expanded te
  group by te.tag
),
linked_duplicates as (
  select pl.RelatedPostId as CanonicalId,
         count(*) as dup_count
  from PostLinks pl
  where pl.LinkTypeId = 3
    and pl.RelatedPostId in (select QuestionId from recent_questions)
  group by pl.RelatedPostId
),
closed_reasons as (
  select ph.PostId as QuestionId,
         max(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as was_closed,
         max(case when ph.PostHistoryTypeId = 10 then try_cast(ph.Comment as int) end) as close_reason_id,
         max(case when ph.PostHistoryTypeId in (11,13) then 1 else 0 end) as was_reopened_or_undeleted
  from PostHistory ph
  where ph.PostId in (select QuestionId from recent_questions)
  group by ph.PostId
),
per_tag_metrics as (
  select te.tag,
         count(*) as q_count,
         avg(q.Score) as avg_q_score,
         percentile_cont(0.5) within group (order by q.ViewCount) as p50_views,
         avg(qa.comment_count) as avg_comments,
         avg(qa.net_votes) as avg_net_votes,
         avg(coalesce(ans.answer_count,0)) as avg_answers,
         sum(case when cr.was_closed = 1 then 1 else 0 end) as closed_q,
         sum(case when aa.accepted_answerer_rep is not null then 1 else 0 end) as with_accepted,
         avg(coalesce(aa.accepted_answerer_rep,0)) as avg_acc_ans_rep
  from tag_expanded te
  join recent_questions q on q.QuestionId = te.QuestionId
  left join question_activity qa on qa.QuestionId = te.QuestionId
  left join answer_stats ans on ans.QuestionId = te.QuestionId
  left join accepted_answerer_rep aa on aa.QuestionId = te.QuestionId
  left join closed_reasons cr on cr.QuestionId = te.QuestionId
  group by te.tag
),
heavy_users as (
  select u.Id as UserId,
         count(*) as q_count_year,
         sum(p.Score) as total_q_score_year,
         sum(coalesce(p.ViewCount,0)) as total_q_views_year
  from Users u
  join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
  where p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
  group by u.Id
  having count(*) >= 5
),
engagement_windows as (
  select q.QuestionId,
         min(c.CreationDate) filter (where c.Id is not null) as first_comment_ts,
         min(v.CreationDate) filter (where v.VoteTypeId in (2,3)) as first_vote_ts,
         min(a.CreationDate) filter (where a.Id is not null) as first_answer_ts
  from recent_questions q
  left join Comments c on c.PostId = q.QuestionId
  left join Votes v on v.PostId = q.QuestionId
  left join Posts a on a.ParentId = q.QuestionId and a.PostTypeId = 2
  group by q.QuestionId
),
final_rank as (
  select te.tag,
         tm.q_count,
         tm.avg_q_score,
         tm.p50_views,
         tm.avg_comments,
         tm.avg_net_votes,
         tm.avg_answers,
         tm.closed_q,
         tm.with_accepted,
         tm.avg_acc_ans_rep,
         tp.tag_q_count as global_tag_q_count,
         tp.tag_total_score,
         tp.tag_total_views,
         rank() over (order by tm.q_count desc, tm.avg_q_score desc, tm.avg_answers desc) as tag_rank
  from per_tag_metrics tm
  join tag_popularity tp on tp.tag = tm.tag
  join (select tag from tag_popularity where tag_q_count >= 25) te on te.tag = tm.tag
)
select
  fr.tag,
  fr.tag_rank,
  fr.q_count as questions_in_last_year,
  round(fr.avg_q_score::numeric, 2) as avg_question_score,
  fr.p50_views as median_views,
  round(fr.avg_comments::numeric, 2) as avg_comments,
  round(fr.avg_net_votes::numeric, 2) as avg_net_votes,
  round(fr.avg_answers::numeric, 2) as avg_answers,
  fr.closed_q as closed_questions,
  fr.with_accepted as with_accepted_answers,
  round(fr.avg_acc_ans_rep::numeric, 2) as avg_accepted_answerer_rep,
  fr.global_tag_q_count as lifetime_questions_for_tag,
  fr.tag_total_score as lifetime_tag_total_score,
  fr.tag_total_views as lifetime_tag_total_views,
  (
    select round(avg(extract(epoch from (least(coalesce(ew.first_answer_ts, now()), coalesce(ew.first_comment_ts, now()), coalesce(ew.first_vote_ts, now())) - q.CreationDate))/3600.0)::numeric, 2)
    from tag_expanded te2
    join recent_questions q on q.QuestionId = te2.QuestionId
    left join engagement_windows ew on ew.QuestionId = q.QuestionId
    where te2.tag = fr.tag
  ) as avg_first_engagement_hours,
  (
    select count(*)
    from tag_expanded te3
    join recent_questions q on q.QuestionId = te3.QuestionId
    left join linked_duplicates ld on ld.CanonicalId = q.QuestionId
    where te3.tag = fr.tag and coalesce(ld.dup_count,0) > 0
  ) as canonical_duplicates_count,
  (
    select count(*)
    from tag_expanded te4
    join recent_questions q on q.QuestionId = te4.QuestionId
    left join closed_reasons cr on cr.QuestionId = q.QuestionId
    where te4.tag = fr.tag and cr.was_closed = 1 and coalesce(cr.close_reason_id,0) in (101,102,103,104,105)
  ) as closed_current_reasons_count,
  (
    select count(distinct u.Id)
    from tag_expanded te5
    join recent_questions q on q.QuestionId = te5.QuestionId
    join Users u on u.Id = q.OwnerUserId
    where te5.tag = fr.tag
  ) as distinct_askers_last_year,
  (
    select count(*)
    from tag_expanded te6
    join recent_questions q on q.QuestionId = te6.QuestionId
    join heavy_users hu on hu.UserId = q.OwnerUserId
    where te6.tag = fr.tag
  ) as questions_by_heavy_askers
from final_rank fr
order by fr.tag_rank
limit 50;