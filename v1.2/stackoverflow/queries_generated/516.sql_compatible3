with recursive RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsRequired = true
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        r.Level + 1 as Level,
        r.Path || '>' || t.TagName as Path
    from RecursiveTagHierarchy r
    join Tags t on t.Id = r.Id + 1 and t.IsModeratorOnly = false
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
TopUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(ubc_gold.BadgeCount, 0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount, 0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount, 0) as BronzeBadges,
        row_number() over (order by u.Reputation desc, u.CreationDate asc) as UserRank
    from Users u
    left join UserBadgeCounts ubc_gold on u.Id = ubc_gold.UserId and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on u.Id = ubc_silver.UserId and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on u.Id = ubc_bronze.UserId and ubc_bronze.Class = 3
    where u.Reputation > 1000
),
PostStats as (
    select
        p.OwnerUserId,
        count(case when p.PostTypeId = 1 then 1 end) as QuestionCount,
        count(case when p.PostTypeId = 2 then 1 end) as AnswerCount,
        avg(case when p.PostTypeId in (1,2) then p.Score end) as AvgScore,
        max(case when p.PostTypeId in (1,2) then p.Score end) as MaxScore,
        sum(case when p.PostTypeId = 1 then p.ViewCount else 0 end) as TotalViews,
        count(distinct case when p.AcceptedAnswerId is not null then p.Id end) as QuestionsWithAcceptedAnswer
    from Posts p
    group by p.OwnerUserId
),
UserActivityWindow as (
    select
        p.OwnerUserId,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        count(*) over (partition by p.OwnerUserId order by p.CreationDate rows between 29 preceding and current row) as PostsLast30Days,
        sum(p.Score) over (partition by p.OwnerUserId order by p.CreationDate rows between 29 preceding and current row) as ScoreLast30Days
    from Posts p
    where p.OwnerUserId is not null
),
PostLinksWithDuplicates as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.PostTypeId as PostType,
        p2.PostTypeId as RelatedPostType
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    join Posts p1 on pl.PostId = p1.Id
    join Posts p2 on pl.RelatedPostId = p2.Id
    where lt.Name in ('Duplicate', 'Linked')
),
QuestionsWithCloseInfo as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.ClosedDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        cr.Name as CloseReason,
        ph.CreationDate as CloseVoteDate
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes cr on cast(ph.Comment as integer) = cr.Id
    where p.PostTypeId = 1
),
UserCommentStats as (
    select
        c.UserId,
        count(*) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        sum(case when c.Text like '%SQL%' then 1 else 0 end) as SQLComments
    from Comments c
    group by c.UserId
),
FinalResult as (
    select
        tu.UserRank,
        tu.DisplayName,
        tu.Reputation,
        tu.Location,
        tu.GoldBadges,
        tu.SilverBadges,
        tu.BronzeBadges,
        coalesce(ps.QuestionCount,0) as QuestionCount,
        coalesce(ps.AnswerCount,0) as AnswerCount,
        coalesce(ps.AvgScore,0) as AvgPostScore,
        coalesce(ps.MaxScore,0) as MaxPostScore,
        coalesce(ps.TotalViews,0) as TotalQuestionViews,
        coalesce(ps.QuestionsWithAcceptedAnswer,0) as QuestionsWithAcceptedAnswer,
        coalesce(uas.PostsLast30Days,0) as PostsLast30Days,
        coalesce(uas.ScoreLast30Days,0) as ScoreLast30Days,
        coalesce(ucs.CommentCount,0) as CommentCount,
        coalesce(ucs.AvgCommentLength,0) as AvgCommentLength,
        coalesce(ucs.SQLComments,0) as SQLComments,
        (select count(*) from PostLinksWithDuplicates pld where pld.PostType = 1 and pld.PostId in (
            select Id from Posts where OwnerUserId = tu.Id
        )) as LinkedPostsCount,
        (select count(distinct ph.PostId) from PostHistory ph where ph.UserId = tu.Id and ph.PostHistoryTypeId in (10,11)) as CloseReopenActions
    from TopUsers tu
    left join PostStats ps on tu.Id = ps.OwnerUserId
    left join (
        select OwnerUserId, max(PostsLast30Days) as PostsLast30Days, max(ScoreLast30Days) as ScoreLast30Days
        from UserActivityWindow
        group by OwnerUserId
    ) uas on tu.Id = uas.OwnerUserId
    left join UserCommentStats ucs on tu.Id = ucs.UserId
    where tu.UserRank <= 100
)
select
    fr.UserRank,
    fr.DisplayName,
    fr.Reputation,
    fr.Location,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.QuestionCount,
    fr.AnswerCount,
    fr.AvgPostScore,
    fr.MaxPostScore,
    fr.TotalQuestionViews,
    fr.QuestionsWithAcceptedAnswer,
    fr.PostsLast30Days,
    fr.ScoreLast30Days,
    fr.CommentCount,
    fr.AvgCommentLength,
    fr.SQLComments,
    fr.LinkedPostsCount,
    fr.CloseReopenActions,
    case
        when fr.GoldBadges > 10 then 'Elite'
        when fr.SilverBadges > 20 then 'Experienced'
        when fr.BronzeBadges > 50 then 'Active'
        else 'Newbie'
    end as UserLevel,
    case
        when fr.AvgPostScore >= 10 then 'High Quality'
        when fr.AvgPostScore between 5 and 9 then 'Moderate Quality'
        else 'Low Quality'
    end as PostQualityCategory,
    case
        when fr.PostsLast30Days > 10 then 'Highly Active'
        when fr.PostsLast30Days between 1 and 10 then 'Moderately Active'
        else 'Inactive'
    end as RecentActivityLevel,
    concat(
        coalesce(fr.Location, 'Unknown Location'),
        ' | ',
        'Reputation: ', cast(fr.Reputation as varchar),
        ' | ',
        'Questions: ', cast(fr.QuestionCount as varchar),
        ' | ',
        'Answers: ', cast(fr.AnswerCount as varchar)
    ) as SummaryInfo
from FinalResult fr
order by fr.Reputation desc, fr.UserRank asc
limit 50;