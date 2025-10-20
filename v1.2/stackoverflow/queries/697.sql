with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (partition by t.Id order by p.CreationDate desc) as rn
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
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
    having u.Reputation > 10000
),
UserActivity as (
    select
        u.Id as UserId,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsAsked,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersGiven,
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
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedCount,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount
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
        coalesce(pla.LinkedCount,0) as LinkedCount,
        coalesce(pla.DuplicateCount,0) as DuplicateCount,
        u.DisplayName as OwnerName,
        coalesce(ua.QuestionsAsked,0) as QuestionsAsked,
        coalesce(ua.AnswersGiven,0) as AnswersGiven,
        coalesce(ua.TotalUpVotes,0) as TotalUpVotes,
        coalesce(ua.TotalDownVotes,0) as TotalDownVotes,
        coalesce(ua.CommentsMade,0) as CommentsMade,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as UserTopQuestionRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join UserActivity ua on ua.UserId = p.OwnerUserId
    left join PostLinkAggregates pla on pla.PostId = p.Id
    where p.PostTypeId = 1
),
RankedQuestions as (
    select
        qs.Id,
        qs.Title,
        qs.Tags,
        qs.CreationDate,
        qs.Score,
        qs.ViewCount,
        qs.AnswerCount,
        qs.FavoriteCount,
        qs.LinkedCount,
        qs.DuplicateCount,
        qs.OwnerName,
        qs.QuestionsAsked,
        qs.AnswersGiven,
        qs.TotalUpVotes,
        qs.TotalDownVotes,
        qs.CommentsMade,
        qs.UserTopQuestionRank,
        lag(qs.Score) over (order by qs.Score desc) as PrevScore,
        lead(qs.Score) over (order by qs.Score desc) as NextScore,
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
        ( 'Score: ' || coalesce(cast(fhq.Score as varchar), '') 
          || ' | Views: ' || coalesce(cast(fhq.ViewCount as varchar), '') 
          || ' | Answers: ' || coalesce(cast(fhq.AnswerCount as varchar), '') 
          || ' | Favorites: ' || coalesce(cast(fhq.FavoriteCount as varchar), '')
          || ' | Linked: ' || coalesce(cast(fhq.LinkedCount as varchar), '')
          || ' | Duplicates: ' || coalesce(cast(fhq.DuplicateCount as varchar), '')
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
order by ScoreViewProduct desc, CreationDate desc
limit 50;