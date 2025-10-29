-- {"query": "2425.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1551}
with RecursiveUserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (partition by u.Id order by b.Date desc nulls last) as BadgeRank,
        b.Date
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, b.Date
), LatestBadgePerUser as (
    select *
    from RecursiveUserBadgeCounts
    where BadgeRank = 1
), PostScoresAgg as (
    select
        p.OwnerUserId as UserId,
        sum(case when p.PostTypeId = 1 then p.Score else 0 end) as TotalQuestionScore,
        sum(case when p.PostTypeId = 2 then p.Score else 0 end) as TotalAnswerScore,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount,
        max(p.Score) as MaxPostScore,
        avg(p.Score) filter (where p.Score > 0) as AvgPositiveScore,
        bool_or(p.ClosedDate is not null) as HasClosedPosts
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
), UserCommentsSummary as (
    select
        c.UserId,
        count(*) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        sum(case when c.Score is null then 0 else c.Score end) as TotalCommentScore
    from Comments c
    where c.UserId is not null
    group by c.UserId
), DuplicateLinks as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
), QuestionAnswerRank as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
), TopAnswersWithComments as (
    select
        qar.AnswerId,
        qar.QuestionId,
        qar.AnswerScore,
        qar.AnswerRank,
        coalesce(comment_stats.CommentCount,0) as AnswerCommentCount,
        coalesce(comment_stats.AvgCommentLength,0) as AnswerAvgCommentLen
    from QuestionAnswerRank qar
    left join (
        select
            c.PostId,
            count(*) as CommentCount,
            avg(length(c.Text)) as AvgCommentLength
        from Comments c
        group by c.PostId
    ) comment_stats on comment_stats.PostId = qar.AnswerId
    where qar.AnswerRank = 1
), UserActivityRatio as (
    select
        u.Id as UserId,
        case when u.UpVotes = 0 then null else (cast(u.DownVotes as float) / u.UpVotes) end as DownToUpVoteRatio,
        date_part('epoch', u.LastAccessDate - u.CreationDate)/86400.0 as DaysActive,
        case when date_part('epoch', u.LastAccessDate - u.CreationDate) < 0 then null
             else (cast(u.Views as float) / nullif(date_part('epoch', u.LastAccessDate - u.CreationDate)/86400.0,0))
        end as ViewsPerDay
    from Users u
), ComplexUserMetrics as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        p.TotalQuestionScore,
        p.TotalAnswerScore,
        p.QuestionCount,
        p.AnswerCount,
        p.MaxPostScore,
        p.AvgPositiveScore,
        p.HasClosedPosts,
        c.CommentCount,
        c.AvgCommentLength as CommentAvgLen,
        c.TotalCommentScore,
        d.DuplicateCount,
        l.GoldBadges,
        l.SilverBadges,
        l.BronzeBadges,
        ua.DownToUpVoteRatio,
        ua.DaysActive,
        ua.ViewsPerDay,
        case 
            when p.QuestionCount > 0 then cast(p.TotalQuestionScore as float) / p.QuestionCount
            else null
        end as AvgScorePerQuestion,
        case 
            when p.AnswerCount > 0 then cast(p.TotalAnswerScore as float) / p.AnswerCount
            else null
        end as AvgScorePerAnswer,
        case
            when coalesce(l.GoldBadges,0) + coalesce(l.SilverBadges,0) + coalesce(l.BronzeBadges,0) = 0 then 0
            else (coalesce(l.GoldBadges,0) * 3 + coalesce(l.SilverBadges,0) * 2 + coalesce(l.BronzeBadges,0)) * 1.0 / (coalesce(l.GoldBadges,0) + coalesce(l.SilverBadges,0) + coalesce(l.BronzeBadges,0))
        end as WeightedBadgeScore
    from Users u
    left join PostScoresAgg p on p.UserId = u.Id
    left join UserCommentsSummary c on c.UserId = u.Id
    left join DuplicateLinks d on d.PostId = (
        select p2.Id from Posts p2 where p2.OwnerUserId = u.Id order by p2.Score desc limit 1
    )
    left join LatestBadgePerUser l on l.UserId = u.Id
    left join UserActivityRatio ua on ua.UserId = u.Id
)
select
    cum.Id as UserId,
    cum.DisplayName,
    cum.Reputation,
    cum.TotalQuestionScore,
    cum.TotalAnswerScore,
    cum.QuestionCount,
    cum.AnswerCount,
    cum.MaxPostScore,
    cum.AvgPositiveScore,
    cum.HasClosedPosts,
    cum.CommentCount,
    cum.CommentAvgLen,
    cum.TotalCommentScore,
    cum.DuplicateCount,
    cum.GoldBadges,
    cum.SilverBadges,
    cum.BronzeBadges,
    cum.DownToUpVoteRatio,
    cum.DaysActive,
    cum.ViewsPerDay,
    cum.AvgScorePerQuestion,
    cum.AvgScorePerAnswer,
    cum.WeightedBadgeScore,
    concat(
        'User ', coalesce(cum.DisplayName, 'unknown'), 
        ' has a rep of ', cum.Reputation, 
        ', with ', coalesce(cum.GoldBadges,0), ' gold, ', coalesce(cum.SilverBadges,0), ' silver and ', coalesce(cum.BronzeBadges,0), ' bronze badges.'
    ) as UserSummary,
    case 
        when cum.HasClosedPosts then 'Has closed posts'
        else 'No closed posts'
    end as ClosureStatus
from ComplexUserMetrics cum
where cum.Reputation > (
    select percentile_cont(0.75) within group (order by Reputation) from Users
)
and cum.QuestionCount > 0
order by cum.WeightedBadgeScore desc, cum.AvgScorePerAnswer desc nulls last, cum.DaysActive desc
limit 50;