-- {"query": "2906.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1280} 
with RankedPosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc, p.CreationDate desc) as rn
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1,2) 
      and p.Score is not null
),
TopQuestions with AcceptedAnswers as (
    select 
        q.Id as QuestionId,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.Tags,
        q.OwnerUserId as QuestionOwnerId,
        q.OwnerName as QuestionOwnerName,
        q.OwnerReputation as QuestionOwnerRep,
        a.Id as AnswerId,
        a.CreationDate as AnswerCreation,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerId,
        ua.DisplayName as AnswerOwnerName,
        ua.Reputation as AnswerOwnerRep,
        case 
            when a.Id = q.AcceptedAnswerId then 1 else 0 
        end as IsAcceptedAnswer,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from RankedPosts q
    left join RankedPosts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users ua on a.OwnerUserId = ua.Id
    where q.PostTypeId = 1 and q.rn <= 100
),
AnsweredQuestionsAggregates as (
    select
        QuestionId,
        count(AnswerId) filter (where AnswerId is not null) as AnswerCount,
        sum(AnswerScore) filter (where AnswerId is not null) as TotalAnswerScore,
        max(AnswerScore) filter (where AnswerId is not null) as MaxAnswerScore,
        sum(case when IsAcceptedAnswer = 1 then 1 else 0 end) as AcceptedFlagCount
    from TopQuestions with AcceptedAnswers
    group by QuestionId
),
UserBadgesRanked as (
    select 
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        dense_rank() over (partition by b.UserId order by b.Class asc, b.Date desc) as BadgeRank
    from Badges b
    where b.Date > (current_date - interval '1 year')
),
UsersBadgeSummary as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(b.BadgeName) filter (where b.Class = 1) as GoldBadgesLastYear,
        count(b.BadgeName) filter (where b.Class = 2) as SilverBadgesLastYear,
        count(b.BadgeName) filter (where b.Class = 3) as BronzeBadgesLastYear,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on u.Id = b.UserId and b.Date > (current_date - interval '1 year')
    group by u.Id, u.DisplayName, u.Reputation
),
DuplicateLinks as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        row_number() over (partition by pl.PostId order by pl.CreationDate desc) as rn_dup
    from PostLinks pl
    where pl.LinkTypeId = 3
),
PostsWithDuplicateFlag as (
    select 
        p.*,
        case when dl.PostId is not null then 1 else 0 end as IsMarkedDuplicate
    from Posts p
    left join DuplicateLinks dl on p.Id = dl.PostId and dl.rn_dup = 1
),
WindowedComments as (
    select
        c.PostId,
        c.UserId,
        c.CreationDate,
        c.Score,
        c.Text,
        rank() over (partition by c.PostId order by c.Score desc, c.CreationDate asc) as CommentRank
    from Comments c
    where c.Score is not null
),
TopComments as (
    select 
        wc.PostId,
        string_agg(wc.Text, ' | ' order by wc.CommentRank) as TopCommentsTexts,
        count(wc.Text) as TotalCommentsCount,
        avg(wc.Score) as AvgCommentScore
    from WindowedComments wc
    where wc.CommentRank <= 3
    group by wc.PostId
)

select 
    q.QuestionId,
    q.QuestionCreation,
    q.QuestionScore,
    q.QuestionViews,
    coalesce(nullif(q.Tags,''), '[no-tags]') as QuestionTags,
    q.QuestionOwnerName,
    q.QuestionOwnerRep,
    a.AnswerCount,
    a.TotalAnswerScore,
    a.MaxAnswerScore,
    a.AcceptedFlagCount,
    ubs.GoldBadgesLastYear,
    ubs.SilverBadgesLastYear,
    ubs.BronzeBadgesLastYear,
    ubs.LastBadgeDate,
    dup.IsMarkedDuplicate,
    tc.TopCommentsTexts,
    tc.TotalCommentsCount,
    tc.AvgCommentScore
from AnsweredQuestionsAggregates a
inner join TopQuestions q on a.QuestionId = q.QuestionId
left join UsersBadgeSummary ubs on q.QuestionOwnerId = ubs.UserId
left join PostsWithDuplicateFlag dup on q.QuestionId = dup.Id
left join TopComments tc on q.QuestionId = tc.PostId
where q.QuestionScore > (
    select avg(Score) from Posts where PostTypeId = 1
)
and (a.AcceptedFlagCount > 0 or a.MaxAnswerScore > 10)
and (
    dup.IsMarkedDuplicate = 0 
    or dup.IsMarkedDuplicate is null
)
order by q.QuestionScore desc, a.TotalAnswerScore desc
limit 50;