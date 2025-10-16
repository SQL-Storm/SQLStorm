-- {"query": "625.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1128} 
with RecursiveUserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (partition by u.Id order by b.Date desc nulls last) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopUsers as (
    select UserId, DisplayName, Reputation, GoldBadges, SilverBadges, BronzeBadges
    from RecursiveUserBadgeCounts
    where BadgeRank = 1
    and Reputation > 10000
),
QuestionStats as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.AnswerCount,
        p.Tags,
        p.OwnerUserId,
        coalesce(
          (select count(*) from Comments c where c.PostId = p.Id), 0
        ) as CommentCount,
        coalesce(
          (select avg(p2.Score) from Posts p2 where p2.ParentId = p.Id and p2.PostTypeId = 2), 0
        ) as AvgAnswerScore,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as UserTopQuestionRank
    from Posts p
    where p.PostTypeId = 1
),
FilteredQuestions as (
    select * from QuestionStats
    where UserTopQuestionRank <= 3
    and Tags is not null
    and Tags like '%<python>%'
    and (Score > 5 or ViewCount > 1000)
),
UserAnswerStats as (
    select 
        a.OwnerUserId,
        count(*) as AnswerCount,
        sum(a.Score) as TotalAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.Score >= 10 then 1 else 0 end) as HighScoreAnswers
    from Posts a
    where a.PostTypeId = 2
    group by a.OwnerUserId
),
QuestionAnswerJoin as (
    select 
        q.QuestionId,
        q.Title,
        q.CreationDate as QuestionCreation,
        q.ViewCount,
        q.Score as QuestionScore,
        q.AnswerCount,
        q.CommentCount,
        q.AvgAnswerScore,
        u.DisplayName as QuestionOwner,
        ua.AnswerCount,
        ua.TotalAnswerScore,
        ua.AvgAnswerScore as UserAvgAnswerScore,
        ua.MaxAnswerScore,
        ua.HighScoreAnswers
    from FilteredQuestions q
    left join Users u on u.Id = q.OwnerUserId
    left join UserAnswerStats ua on ua.OwnerUserId = q.OwnerUserId
),
RankedQuestions as (
    select *,
        rank() over (order by QuestionScore desc, ViewCount desc, AnswerCount desc) as QuestionRank
    from QuestionAnswerJoin
),
Duplicates as (
    select pl.PostId, pl.RelatedPostId, lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
),
QuestionsWithDuplicates as (
    select q.*, d.RelatedPostId as DuplicateOf
    from RankedQuestions q
    left join Duplicates d on d.PostId = q.QuestionId
),
FinalSelection as (
    select 
        q.QuestionRank,
        q.QuestionId,
        q.Title,
        q.QuestionCreation,
        q.ViewCount,
        q.QuestionScore,
        q.AnswerCount,
        q.CommentCount,
        q.AvgAnswerScore,
        q.QuestionOwner,
        q.AnswerCount as UserAnswerCount,
        q.TotalAnswerScore,
        q.UserAvgAnswerScore,
        q.MaxAnswerScore,
        q.HighScoreAnswers,
        case when q.DuplicateOf is not null then 'Yes' else 'No' end as IsDuplicate,
        coalesce((select count(*) from Votes v where v.PostId = q.QuestionId and v.VoteTypeId = 2), 0) as Upvotes,
        coalesce((select count(*) from Votes v where v.PostId = q.QuestionId and v.VoteTypeId = 3), 0) as Downvotes,
        case 
            when q.ViewCount = 0 then null
            else round(cast(q.QuestionScore as numeric) / q.ViewCount, 4)
        end as ScorePerViewRatio,
        coalesce((select max(ph.CreationDate) from PostHistory ph where ph.PostId = q.QuestionId), q.QuestionCreation) as LastHistoryEdit,
        case 
            when q.CommentCount > 5 and q.AnswerCount > 2 then 'Hot'
            when q.CommentCount > 0 then 'Active'
            else 'Quiet'
        end as ActivityLevel
    from QuestionsWithDuplicates q
    where q.QuestionRank <= 50
)
select * from FinalSelection
order by QuestionRank asc;