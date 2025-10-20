-- {"query": "4061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1501} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.FavoriteCount, 0) as FavoriteCount,
        row_number() over (partition by t.IsModeratorOnly order by t.Count desc, t.TagName) as rn
    from Tags t
    left join (
        select 
            p.Id,
            p.AnswerCount,
            p.FavoriteCount
        from Posts p
        where p.PostTypeId = 1
    ) p on p.Id = t.ExcerptPostId
    where t.IsRequired = 0
), LatestUserBadges as (
    select
        b.UserId,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
), UserReputationWindows as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(b.Id) over (partition by u.Id) as BadgeCount,
        max(b.Date) over (partition by u.Id) as LastBadgeReceived,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc nulls last) as UserRank
    from Users u
    left join Badges b on b.UserId = u.Id
    where u.Reputation >= 1000
), PostActivityRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc nulls last, p.ViewCount desc nulls last) as ScoreRank,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer
    from Posts p
    where p.PostTypeId in (1,2)
), PostDuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        l.Name as LinkTypeName
    from PostLinks pl
    inner join LinkTypes l on l.Id = pl.LinkTypeId
    where pl.LinkTypeId = 3 -- duplicates
), CorrelatedAnswerStats as (
    select
        q.Id as QuestionId,
        count(a.Id) as TotalAnswers,
        sum(case when a.Score > 0 then 1 else 0 end) as PositiveScoreAnswers,
        sum(case when a.Score < 0 then 1 else 0 end) as NegativeScoreAnswers,
        max(a.Score) as MaxAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id
), QualifiedQuestions as (
    select
        q.Id,
        q.Title,
        q.Tags,
        q.Score,
        q.ViewCount,
        q.OwnerUserId,
        q.AcceptedAnswerId,
        q.AnswerCount,
        ast.TotalAnswers,
        ast.PositiveScoreAnswers,
        ast.NegativeScoreAnswers,
        ast.MaxAnswerScore,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        br.BadgeCount,
        br.LastBadgeReceived
    from Posts q
    left join CorrelatedAnswerStats ast on ast.QuestionId = q.Id
    left join Users u on u.Id = q.OwnerUserId
    left join (
        select
            UserId,
            count(Id) as BadgeCount,
            max(Date) as LastBadgeReceived
        from Badges
        group by UserId
    ) br on br.UserId = q.OwnerUserId
    where q.PostTypeId = 1
      and q.Score > 5
      and q.AnswerCount > 0
      and (br.BadgeCount > 1 or br.BadgeCount is null)
), TitleTagAnalysis as (
    select
        q.Id,
        q.Title,
        q.Tags,
        unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags) - 2), '><')) as Tag,
        length(q.Title) - length(replace(lower(q.Title), 'sql', '')) / 3 as SqlKeywordCount
    from QualifiedQuestions q
), TagRankings as (
    select
        t.Tag,
        count(t.Id) as QuestionsWithTag,
        sum(t.SqlKeywordCount) as TotalSqlKeywordMentions,
        avg(q.Score) as AvgQuestionScore
    from TitleTagAnalysis t
    inner join QualifiedQuestions q on q.Id = t.Id
    group by t.Tag
    having count(t.Id) > 5
), CombinedUserStats as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        b.Name as BadgeName,
        v.VoteTypeId,
        vt.Name as VoteTypeName,
        count(*) as VoteCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) over (partition by u.Id) as TotalUpvotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) over (partition by u.Id) as TotalDownvotes
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    where u.Reputation > 500
), FinalResults as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.OwnerDisplayName,
        q.OwnerReputation,
        coalesce(t.TotalSqlKeywordMentions, 0) as SqlKeywordMentionsInTags,
        coalesce(u.TotalUpvotes, 0) as OwnerUpvotes,
        coalesce(u.TotalDownvotes, 0) as OwnerDownvotes,
        coalesce(u.BadgeName, 'No Badge') as OwnerTopBadge,
        q.MaxAnswerScore,
        q.PositiveScoreAnswers,
        q.NegativeScoreAnswers,
        q.LastBadgeReceived,
        d.RelatedPostId as DuplicateOfQuestionId
    from QualifiedQuestions q
    left join TagRankings t on position(t.Tag in q.Tags) > 0
    left join CombinedUserStats u on u.DisplayName = q.OwnerDisplayName
    left join PostDuplicateLinks d on d.PostId = q.Id
    where q.MaxAnswerScore is not null
)
select
    QuestionId,
    Title,
    Score,
    ViewCount,
    AnswerCount,
    OwnerDisplayName,
    OwnerReputation,
    SqlKeywordMentionsInTags,
    OwnerUpvotes,
    OwnerDownvotes,
    OwnerTopBadge,
    MaxAnswerScore,
    PositiveScoreAnswers,
    NegativeScoreAnswers,
    LastBadgeReceived,
    DuplicateOfQuestionId
from FinalResults
order by Score desc, ViewCount desc
limit 100;