with recursive RecursiveTagHierarchy as (
    select p.Id as PostId, t.Id as TagId, t.TagName, 1 as Level, p.Tags
    from Posts p
    join Tags t on position('<' || t.TagName || '>' in coalesce(p.Tags, '')) > 0
    where p.PostTypeId = 1
    union all
    select pl.RelatedPostId as PostId, t.Id, t.TagName, r.Level + 1, p.Tags
    from PostLinks pl
    join RecursiveTagHierarchy r on pl.PostId = r.PostId and pl.LinkTypeId = 3
    join Posts p on pl.RelatedPostId = p.Id
    join Tags t on position('<' || t.TagName || '>' in coalesce(p.Tags, '')) > 0
),
UserBadgeStats AS (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        coalesce(sum(v.BountyAmount),0) as TotalBountyGiven
    from Users u
    left join Badges b on u.Id = b.UserId
    left join Votes v on v.UserId = u.Id and v.VoteTypeId = 8
    group by u.Id, u.DisplayName
),
PostScoreRankings as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.CreationDate asc) as ScoreRank,
        count(*) over (partition by p.OwnerUserId, p.PostTypeId) as PostCountByUserType,
        coalesce(p.ViewCount, 0) as Views,
        p.Tags,
        p.AcceptedAnswerId
    from Posts p
    where p.PostTypeId in (1, 2)
),
MaxCommentScoresPerPost as (
    select PostId, max(Score) as MaxCommentScore
    from Comments
    group by PostId
),
AcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.CreationDate as QuestionCreated,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreated,
        u.DisplayName as AnswerAuthor,
        case when a.Score > 0 then 'Positive' else 'Non-positive' end as AnswerScoreCategory
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    left join Users u on a.OwnerUserId = u.Id
    where q.PostTypeId = 1
),
UserActivity AS (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as TotalQuestions,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as TotalAnswers,
        count(distinct c.Id) as TotalComments,
        avg(case when p.PostTypeId = 1 then p.Score end) as AvgQuestionScore,
        avg(case when p.PostTypeId = 2 then p.Score end) as AvgAnswerScore,
        max(p.LastActivityDate) as LastActivity
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostsWithComplexTagCalculations as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        case when p.Tags is null or length(p.Tags) < 2 then 0
             else array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'), 1)
        end as TagCount,
        position('sql' in lower(coalesce(p.Body, ''))) as PositionSqlKeyword,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed
    from Posts p where p.PostTypeId = 1
),
TopUsersPerTag as (
    select
        tag.TagName,
        u.DisplayName,
        count(p.Id) as PostsWithTag,
        sum(p.Score) as TotalScore,
        rank() over (partition by tag.TagName order by sum(p.Score) desc) as UserRankForTag
    from Posts p
    join Tags tag on position('<' || tag.TagName || '>' in coalesce(p.Tags, '')) > 0
    join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
    group by tag.TagName, u.DisplayName
)
select
    p.Id as QuestionId,
    p.Title,
    p.OwnerUserId,
    u.DisplayName as OwnerName,
    p.Score,
    p.ViewCount,
    p.TagCount,
    p.PositionSqlKeyword,
    p.IsClosed,
    abs(coalesce(ms.MaxCommentScore,0)) as MaxCommentAbsoluteScore,
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.TotalBountyGiven,
    ua.TotalPosts, ua.TotalQuestions, ua.TotalAnswers, ua.TotalComments, ua.AvgQuestionScore, ua.AvgAnswerScore,
    aa.AnswerId as AcceptedAnswerId,
    aa.AnswerScore,
    aa.AnswerAuthor,
    aa.AnswerScoreCategory,
    string_agg(distinct rth.TagName, ', ') as RecursiveDuplicateTags,
    count(distinct pl.Id) as DuplicateLinkCount,
    count(distinct linkage.Id) as LinkedQuestionsCount
from PostsWithComplexTagCalculations p
left join UserBadgeStats ub on ub.UserId = p.OwnerUserId
left join UserActivity ua on ua.Id = p.OwnerUserId
left join AcceptedAnswerStats aa on aa.QuestionId = p.Id
left join MaxCommentScoresPerPost ms on ms.PostId = p.Id
left join RecursiveTagHierarchy rth on rth.PostId = p.Id and rth.Level <= 3
left join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3
left join PostLinks linkage on linkage.PostId = p.Id and linkage.LinkTypeId = 1
left join Users u on u.Id = p.OwnerUserId
where p.Score > 0
group by p.Id, p.Title, p.OwnerUserId, u.DisplayName, p.Score, p.ViewCount, p.TagCount, p.PositionSqlKeyword, p.IsClosed, ms.MaxCommentScore, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.TotalBountyGiven, ua.TotalPosts, ua.TotalQuestions, ua.TotalAnswers, ua.TotalComments, ua.AvgQuestionScore, ua.AvgAnswerScore, aa.AnswerId, aa.AnswerScore, aa.AnswerAuthor, aa.AnswerScoreCategory
having count(distinct pl.Id) > 0
order by p.Score desc, p.ViewCount desc
limit 50;