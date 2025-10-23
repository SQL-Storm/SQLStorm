-- {"query": "697.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1329} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (partition by t.Id order by p.CreationDate desc nulls last) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
),
LatestTagInfo as (
    select Id, TagName, Count, AnswerCount, ViewCount, Score
    from RecursiveTagCounts
    where rn = 1
),
TopUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        dense_rank() over (order by u.Reputation desc) as ReputationRank,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
    having u.Reputation > 10000
),
UserActivity as (
    select
        u.Id as UserId,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        coalesce(sum(vtUp.VoteCount),0) as TotalUpVotes,
        coalesce(sum(vtDown.VoteCount),0) as TotalDownVotes,
        max(p.CreationDate) as LastPostDate,
        count(distinct c.Id) as CommentsMade
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId = 2
        group by PostId
    ) vtUp on vtUp.PostId = p.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId = 3
        group by PostId
    ) vtDown on vtDown.PostId = p.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id
),
PostLinkAggregates as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Linked') as LinkedCount,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
QuestionStats as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        pla.LinkedCount,
        pla.DuplicateCount,
        u.DisplayName as OwnerName,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        ua.CommentsMade,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as UserTopQuestionRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join UserActivity ua on ua.UserId = p.OwnerUserId
    left join PostLinkAggregates pla on pla.PostId = p.Id
    where p.PostTypeId = 1
),
RankedQuestions as (
    select
        qs.*,
        lag(qs.Score) over (order by qs.Score desc nulls last) as PrevScore,
        lead(qs.Score) over (order by qs.Score desc nulls last) as NextScore,
        case when qs.Score is null then 0 else qs.Score end * coalesce(qs.ViewCount,0) as ScoreViewProduct,
        (select count(1) from Comments c where c.PostId = qs.Id and c.CreationDate > qs.CreationDate) as CommentsAfterPost
    from QuestionStats qs
),
FilteredHighImpactQuestions as (
    select *
    from RankedQuestions
    where Score > 10
      and ViewCount > 1000
      and (LinkedCount > 5 or DuplicateCount > 0)
      and (QuestionsAsked > 5 or AnswersGiven > 10)
      and (CommentsAfterPost > 3 or FavoriteCount > 2)
),
FinalResult as (
    select
        fhq.Id,
        fhq.Title,
        fhq.Tags,
        fhq.CreationDate,
        fhq.Score,
        fhq.ViewCount,
        fhq.AnswerCount,
        fhq.FavoriteCount,
        fhq.LinkedCount,
        fhq.DuplicateCount,
        fhq.OwnerName,
        fhq.QuestionsAsked,
        fhq.AnswersGiven,
        fhq.TotalUpVotes,
        fhq.TotalDownVotes,
        fhq.CommentsMade,
        fhq.PrevScore,
        fhq.NextScore,
        fhq.ScoreViewProduct,
        fhq.CommentsAfterPost,
        concat_ws(' | ',
            'Score:', fhq.Score::text,
            'Views:', fhq.ViewCount::text,
            'Answers:', fhq.AnswerCount::text,
            'Favorites:', fhq.FavoriteCount::text,
            'Linked:', fhq.LinkedCount::text,
            'Duplicates:', fhq.DuplicateCount::text
        ) as SummaryStats,
        case
            when fhq.Score >= 50 then 'Hot'
            when fhq.Score >= 20 then 'Popular'
            else 'Normal'
        end as PopularityCategory
    from FilteredHighImpactQuestions fhq
)
select *
from FinalResult
order by ScoreViewProduct desc nulls last, CreationDate desc
limit 50;