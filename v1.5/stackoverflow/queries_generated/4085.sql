-- {"query": "4085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1374} 
with RecursiveUserBadgeCTE as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Class as BadgeClass,
        b.Name as BadgeName,
        b.Date as BadgeDate,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    where b.Class is not null
), LatestUserBadges as (
    select 
        UserId,
        DisplayName,
        Reputation,
        BadgeClass,
        BadgeName,
        BadgeDate
    from RecursiveUserBadgeCTE
    where BadgeRank <= 3
), QuestionWithAcceptedDetails as (
    select 
        p.Id as QuestionId,
        p.Title as QuestionTitle,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.CreationDate as AcceptedAnswerCreation,
        u.DisplayName as AcceptedAnswerUser
    from Posts p
    left join Posts a on a.Id = p.AcceptedAnswerId and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where p.PostTypeId = 1
), PostLinksCount as (
    select 
        PostId,
        count(*) filter (where LinkTypeId = 1) as LinkedCount,
        count(*) filter (where LinkTypeId = 3) as DuplicateCount
    from PostLinks
    group by PostId
), PostCommentsStats as (
    select
        PostId,
        count(*) as CommentCount,
        sum(coalesce(Score,0)) as TotalCommentScore,
        max(CreationDate) as LastCommentDate
    from Comments
    group by PostId
), UserActivityRank as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId=1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId=2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        row_number() over (order by u.Reputation desc, u.CreationDate asc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
), TopUsersQuestions as (
    select
        u.Id as UserId,
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount
    from Users u
    join Posts q on q.OwnerUserId = u.Id and q.PostTypeId = 1
    where u.Reputation > 10000
), DuplicateQuestionPairs as (
    select 
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        pl.CreationDate as LinkCreationDate,
        pl.Id as LinkId
    from PostLinks pl
    join Posts pq on pq.Id = pl.PostId and pq.PostTypeId = 1
    join Posts pr on pr.Id = pl.RelatedPostId and pr.PostTypeId = 1
    where pl.LinkTypeId = 3
), FinalCTE as (
    select 
        uar.DisplayName as UserDisplayName,
        uar.Reputation,
        uar.QuestionCount,
        uar.AnswerCount,
        uar.CommentCount,
        lub.BadgeClass,
        lub.BadgeName,
        qwd.QuestionTitle,
        qwd.AcceptedAnswerScore,
        qwd.AcceptedAnswerUser,
        plc.LinkedCount,
        plc.DuplicateCount,
        pcs.CommentCount as PostCommentCount,
        pcs.TotalCommentScore,
        pcs.LastCommentDate,
        dp.DuplicateQuestionId,
        dp.OriginalQuestionId,
        dp.LinkCreationDate,
        dp.LinkId,
        row_number() over (partition by uar.Id order by qwd.AcceptedAnswerScore desc nulls last) as AnswerScoreRank,
        rank() over (partition by uar.Id order by pcs.TotalCommentScore desc nulls last) as CommentPopularityRank,
        case 
            when uar.Reputation > 50000 then 'Elite'
            when uar.Reputation > 20000 then 'High'
            when uar.Reputation > 5000 then 'Medium'
            else 'Low'
        end as ReputationCategory,
        coalesce(qwd.AcceptedAnswerScore,0) * 1.5 + coalesce(pcs.TotalCommentScore,0) * 0.5 as EngagementScore
    from UserActivityRank uar
    left join LatestUserBadges lub on lub.UserId = uar.Id
    left join QuestionWithAcceptedDetails qwd on qwd.OwnerUserId = uar.Id
    left join PostLinksCount plc on plc.PostId = qwd.QuestionId
    left join PostCommentsStats pcs on pcs.PostId = qwd.QuestionId
    left join DuplicateQuestionPairs dp on dp.DuplicateQuestionId = qwd.QuestionId
    where uar.UserRank <= 100
)
select 
    UserDisplayName,
    Reputation,
    QuestionCount,
    AnswerCount,
    CommentCount,
    BadgeClass,
    BadgeName,
    QuestionTitle,
    AcceptedAnswerScore,
    AcceptedAnswerUser,
    LinkedCount,
    DuplicateCount,
    PostCommentCount,
    TotalCommentScore,
    to_char(LastCommentDate, 'YYYY-MM-DD') as LastCommentDate,
    DuplicateQuestionId,
    OriginalQuestionId,
    to_char(LinkCreationDate, 'YYYY-MM-DD') as LinkCreationDate,
    AnswerScoreRank,
    CommentPopularityRank,
    ReputationCategory,
    round(EngagementScore,2) as EngagementScore,
    case 
        when TotalCommentScore is null then 'No comments'
        when TotalCommentScore > 50 then 'Highly commented'
        when TotalCommentScore > 10 then 'Moderately commented'
        else 'Low comments'
    end as CommentVolumeClassification,
    case 
        when AcceptedAnswerScore is null then null
        when AcceptedAnswerScore > 100 then substring(QuestionTitle from 1 for 30) || '...'
        else substring(QuestionTitle from 1 for 50)
    end as QuestionSnippet
from FinalCTE
where QuestionTitle is not null
order by EngagementScore desc, Reputation desc
limit 50;