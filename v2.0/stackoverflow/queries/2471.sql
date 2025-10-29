-- {"query": "2471.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1417}
with ranked_answers as (
  select
    a.Id,
    a.ParentId,
    a.OwnerUserId,
    a.Score,
    a.CreationDate,
    row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as rn,
    dense_rank() over (partition by a.ParentId order by a.Score desc) as dr_score
  from Posts a
  where a.PostTypeId = 2
),
top_answers as (
  select Id, ParentId, OwnerUserId, Score, CreationDate
  from ranked_answers
  where dr_score = 1
),
question_stats as (
  select
    q.Id as QuestionId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.Score as QuestionScore,
    q.ViewCount,
    count(distinct c.Id) as CommentCount,
    coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end), 0) as UpVotes,
    coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end), 0) as DownVotes,
    case when q.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
    ta.Id as TopAnswerId,
    ta.Score as TopAnswerScore,
    u.DisplayName as QuestionOwnerDisplayName,
    u.Reputation as QuestionOwnerReputation,
    substring(coalesce(q.Tags, '') from 2 for char_length(coalesce(q.Tags, '')) - 2) as CleanTags
  from Posts q
  left join Comments c on c.PostId = q.Id
  left join Votes v on v.PostId = q.Id
  left join top_answers ta on ta.ParentId = q.Id
  left join Users u on u.Id = q.OwnerUserId
  where q.PostTypeId = 1
  group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AcceptedAnswerId, ta.Id, ta.Score, u.DisplayName, u.Reputation, q.Tags
),
user_badges as (
  select
    b.UserId,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
  from Badges b
  group by b.UserId
),
question_avg_comment as (
  select
    OwnerUserId,
    avg(CommentCount) over (partition by OwnerUserId) as AvgCommentsPerQuestion
  from question_stats
),
badged_users as (
  select
    u.Id,
    u.DisplayName,
    u.Reputation,
    coalesce(ub.GoldBadges,0) as GoldBadges,
    coalesce(ub.SilverBadges,0) as SilverBadges,
    coalesce(ub.BronzeBadges,0) as BronzeBadges,
    qac.AvgCommentsPerQuestion
  from Users u
  left join user_badges ub on ub.UserId = u.Id
  left join question_avg_comment qac on qac.OwnerUserId = u.Id
),
recent_closures as (
  select
    ph.PostId,
    ph.CreationDate as CloseDate,
    crt.Name as CloseReason,
    ph.UserId as ClosedByUserId,
    u.DisplayName as ClosedByUser
  from PostHistory ph
  left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
  left join Users u on u.Id = ph.UserId
  where ph.PostHistoryTypeId = 10
),
answers_with_links as (
  select distinct a.Id as AnswerId, pl.RelatedPostId as LinkedQuestionId, lt.Name as LinkTypeName
  from Posts a
  inner join PostLinks pl on pl.PostId = a.Id
  inner join LinkTypes lt on lt.Id = pl.LinkTypeId
  where a.PostTypeId = 2
),
final_complex_view as (
  select
    qs.QuestionId,
    qs.Title,
    qs.CreationDate,
    qs.QuestionScore,
    qs.ViewCount,
    qs.CommentCount,
    qs.UpVotes,
    qs.DownVotes,
    qs.HasAcceptedAnswer,
    qs.TopAnswerId,
    qs.TopAnswerScore,
    qs.QuestionOwnerDisplayName,
    qs.QuestionOwnerReputation,
    bu.GoldBadges,
    bu.SilverBadges,
    bu.BronzeBadges,
    bu.AvgCommentsPerQuestion,
    rc.CloseDate,
    rc.CloseReason,
    rc.ClosedByUser,
    array_agg(distinct (LinkTypeName || ':' || coalesce(cast(LinkedQuestionId as varchar(255)), 'NULL'))) filter (where al.AnswerId is not null) as LinksFromAnswers,
    -- Replace aggregate over set-returning function with lateral to expand tags per-row, then count distinct in outer aggregation
    ( select count(distinct tag) from (
        select regexp_split_to_table(trim(both '<>' from coalesce(q.Tags, '')), '><') as tag
      ) t
    ) as DistinctTagCount,
    case 
      when (qs.ViewCount is not null and qs.ViewCount > 10000) or (qs.TopAnswerScore is not null and qs.TopAnswerScore > 50) then 'High Activity'
      else 'Normal Activity'
    end as ActivityStatus
  from question_stats qs
  left join badged_users bu on bu.DisplayName = qs.QuestionOwnerDisplayName
  left join recent_closures rc on rc.PostId = qs.QuestionId
  left join answers_with_links al on al.AnswerId = qs.TopAnswerId
  left join Posts q on q.Id = qs.QuestionId
  group by qs.QuestionId, qs.Title, qs.CreationDate, qs.QuestionScore, qs.ViewCount, qs.CommentCount, qs.UpVotes, qs.DownVotes, qs.HasAcceptedAnswer, qs.TopAnswerId, qs.TopAnswerScore, qs.QuestionOwnerDisplayName, qs.QuestionOwnerReputation, bu.GoldBadges, bu.SilverBadges, bu.BronzeBadges, bu.AvgCommentsPerQuestion, rc.CloseDate, rc.CloseReason, rc.ClosedByUser, q.Tags
)
select *
from final_complex_view
where ActivityStatus = 'High Activity'
order by QuestionScore desc, ViewCount desc
limit 100;