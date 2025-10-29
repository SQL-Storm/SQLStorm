-- {"query": "2484.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1356} 
with RankedAnswers as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId,
    a.Score,
    a.CreationDate,
    row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
  from Posts a
  where a.PostTypeId = 2
),
QuestionVotesAgg as (
  select
    p.Id as QuestionId,
    count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
    count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
    count(distinct v.UserId) as DistinctVoters,
    max(v.CreationDate) as LastVoteDate
  from Posts p
  left join Votes v on v.PostId = p.Id and v.VoteTypeId in (2,3)
  where p.PostTypeId = 1
  group by p.Id
),
UserBadgeStats as (
  select
    u.Id as UserId,
    count(b.Id) filter (where b.Class = 1) as GoldBadges,
    count(b.Id) filter (where b.Class = 2) as SilverBadges,
    count(b.Id) filter (where b.Class = 3) as BronzeBadges,
    bool_or(b.TagBased) as HasTagBasedBadges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id
),
RecentEditedQuestions as (
  select
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.CreationDate,
    p.LastEditDate,
    ph.CreationDate as LastHistoryEditDate,
    ph.UserId as LastEditorUserId
  from Posts p
  left join LATERAL (
    select ph2.CreationDate, ph2.UserId
    from PostHistory ph2
    where ph2.PostId = p.Id and ph2.PostHistoryTypeId in (4,5,6)
    order by ph2.CreationDate desc
    limit 1
  ) ph on true
  where p.PostTypeId = 1 and p.LastEditDate is not null
),
DuplicatePostLinks as (
  select
    pl.PostId,
    pl.RelatedPostId,
    pl.CreationDate
  from PostLinks pl
  where pl.LinkTypeId = 3
),
ComplexQuestionStats as (
  select
    q.Id as QuestionId,
    q.Title,
    q.Score,
    q.ViewCount,
    q.Tags,
    q.CreationDate,
    qa.UpVotes,
    qa.DownVotes,
    qa.DistinctVoters,
    q.AnswerCount,
    ra.AnswerId,
    ra.Score as TopAnswerScore,
    ra.AnswerRank,
    u.Reputation,
    u.DisplayName,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.HasTagBasedBadges,
    rq.LastEditDate,
    rq.LastHistoryEditDate,
    rq.LastEditorUserId,
    dup.RelatedPostId as DuplicateOf
  from Posts q
  join QuestionVotesAgg qa on qa.QuestionId = q.Id
  left join RankedAnswers ra on ra.QuestionId = q.Id and ra.AnswerRank = 1
  left join Users u on u.Id = q.OwnerUserId
  left join UserBadgeStats ub on ub.UserId = q.OwnerUserId
  left join RecentEditedQuestions rq on rq.Id = q.Id
  left join DuplicatePostLinks dup on dup.PostId = q.Id
  where q.PostTypeId = 1
),
FinalResult as (
  select
    QuestionId,
    Title,
    Score,
    ViewCount,
    coalesce(nullif(trim(Tags), ''), '<no-tags>') as Tags,
    to_char(CreationDate, 'YYYY-MM-DD') as Created,
    UpVotes,
    DownVotes,
    DistinctVoters,
    AnswerCount,
    TopAnswerScore,
    Reputation as AuthorReputation,
    DisplayName as AuthorName,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    case when HasTagBasedBadges then 'YES' else 'NO' end as HasTagBadges,
    coalesce(to_char(LastEditDate, 'YYYY-MM-DD'), 'Never Edited') as LastEdit,
    coalesce(to_char(LastHistoryEditDate, 'YYYY-MM-DD'), 'No History Edits') as LastHistoryEdit,
    LastEditorUserId,
    DuplicateOf,
    case
      when Score >= 100 and AnswerCount >= 10 then 'Hot and Answered'
      when Score >= 100 then 'Hot'
      when AnswerCount >= 10 then 'Answered'
      else 'Regular'
    end as QuestionCategory,
    length(Title) as TitleLength,
    length(coalesce(Body, '')) as BodyLength
  from (
    select
      c.*,
      p.Body
    from ComplexQuestionStats c
    left join Posts p on p.Id = c.QuestionId
  ) sub
  where UpVotes > DownVotes
  order by Score desc nulls last, AnswerCount desc nulls last, Created desc nulls last
  limit 100
)
select * from FinalResult
union all
select
  -1 as QuestionId,
  'Summary Row' as Title,
  sum(Score) as Score,
  sum(ViewCount) as ViewCount,
  null as Tags,
  null as Created,
  sum(UpVotes) as UpVotes,
  sum(DownVotes) as DownVotes,
  sum(DistinctVoters) as DistinctVoters,
  sum(AnswerCount) as AnswerCount,
  max(TopAnswerScore) as TopAnswerScore,
  max(AuthorReputation) as AuthorReputation,
  null as AuthorName,
  sum(GoldBadges) as GoldBadges,
  sum(SilverBadges) as SilverBadges,
  sum(BronzeBadges) as BronzeBadges,
  null as HasTagBadges,
  null as LastEdit,
  null as LastHistoryEdit,
  null as LastEditorUserId,
  null as DuplicateOf,
  null as QuestionCategory,
  null as TitleLength,
  null as BodyLength
from FinalResult;