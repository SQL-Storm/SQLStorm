-- {"query": "2694.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1460}
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on b.UserId = u.Id
    where b.Class in (1, 2, 3)
), 
UserPostStats as (
    select 
        u.Id as UserId,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersProvided,
        coalesce(sum(p.Score), 0) as TotalPostScore,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id
),
UserCommentEngagement as (
    select 
        c.UserId,
        count(distinct c.Id) as CommentsMade,
        avg(length(c.Text)) as AvgCommentLength,
        sum(c.Score) as TotalCommentScore
    from Comments c
    group by c.UserId
),
TopTagsPerUser as (
    select
        p.OwnerUserId as UserId,
        tag as Tag,
        count(*) as TagCount,
        row_number() over (partition by p.OwnerUserId order by count(*) desc) as rn
    from (
        select
            Id,
            OwnerUserId,
            regexp_split_to_table(substring(Tags from 2 for length(Tags) - 2), '><') as tag
        from Posts
        where PostTypeId = 1 and Tags is not null
    ) p
    group by p.OwnerUserId, tag
),
ClosedQuestionStats as (
    select
        p.OwnerUserId as UserId,
        count(*) as ClosedQuestionsCount,
        count(*) filter (where ph.PostHistoryTypeId = 10 and ph.Comment = '101') as ClosedAsDuplicate,
        min(p.ClosedDate) as FirstClosedDate
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    where p.PostTypeId = 1 and p.ClosedDate is not null
    group by p.OwnerUserId
),
RecentActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Title,
        p.Id as PostId,
        p.CreationDate as PostCreation,
        ph.CreationDate as LastHistoryEdit,
        first_value(p.Score) over (partition by u.Id order by p.CreationDate desc) as LatestPostScore,
        row_number() over (partition by u.Id order by p.CreationDate desc) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.PostId = p.Id and ph.CreationDate = (
        select max(ph2.CreationDate) 
        from PostHistory ph2 where ph2.PostId = p.Id
    )
    where p.PostTypeId in (1, 2)
),
CombinedUserMetrics as (
    select
        u.Id,
        u.DisplayName,
        coalesce(ups.QuestionsAsked,0) as QuestionsAsked,
        coalesce(ups.AnswersProvided,0) as AnswersProvided,
        coalesce(ups.TotalPostScore,0) as TotalPostScore,
        coalesce(uce.CommentsMade,0) as CommentsMade,
        coalesce(uce.AvgCommentLength,0) as AvgCommentLength,
        coalesce(cqs.ClosedQuestionsCount,0) as ClosedQuestionsCount,
        coalesce(cqs.ClosedAsDuplicate,0) as ClosedAsDuplicate,
        rt.PostId as MostRecentPostId,
        rt.LatestPostScore,
        rub.BadgeName as LatestBadgeName,
        rub.Class as LatestBadgeClass,
        tt.Tag as TopTag
    from Users u
    left join UserPostStats ups on ups.UserId = u.Id
    left join UserCommentEngagement uce on uce.UserId = u.Id
    left join ClosedQuestionStats cqs on cqs.UserId = u.Id
    left join (
        select * from RecentActivity where rn = 1
    ) rt on rt.UserId = u.Id
    left join RecursiveUserBadges rub on rub.UserId = u.Id and rub.rn = 1
    left join TopTagsPerUser tt on tt.UserId = u.Id and tt.rn = 1
),
BadgeCountByClass as (
    select
        UserId,
        Class,
        count(*) as BadgeCount
    from Badges
    group by UserId, Class
),
UserBadgeSummary as (
    select
        UserId,
        coalesce(max(case when Class = 1 then BadgeCount end), 0) as GoldBadges,
        coalesce(max(case when Class = 2 then BadgeCount end), 0) as SilverBadges,
        coalesce(max(case when Class = 3 then BadgeCount end), 0) as BronzeBadges
    from BadgeCountByClass
    group by UserId
)
select
    c.Id as UserId,
    c.DisplayName,
    c.QuestionsAsked,
    c.AnswersProvided,
    c.TotalPostScore,
    c.CommentsMade,
    round(cast(c.AvgCommentLength as numeric), 2) as AvgCommentLength,
    c.ClosedQuestionsCount,
    c.ClosedAsDuplicate,
    c.MostRecentPostId,
    c.LatestPostScore,
    c.LatestBadgeName,
    case c.LatestBadgeClass 
        when 1 then 'Gold' 
        when 2 then 'Silver' 
        when 3 then 'Bronze' 
        else 'None' end as LatestBadgeClass,
    c.TopTag,
    coalesce(ubs.GoldBadges,0) as GoldBadgesOwned,
    coalesce(ubs.SilverBadges,0) as SilverBadgesOwned,
    coalesce(ubs.BronzeBadges,0) as BronzeBadgesOwned,
    case 
        when c.QuestionsAsked > 10 and c.AnswersProvided > 20 then 'Active Contributor'
        when c.QuestionsAsked > 10 then 'Question Asker'
        when c.AnswersProvided > 20 then 'Answer Contributor'
        else 'Occasional User'
    end as UserActivityCategory
from CombinedUserMetrics c
left join UserBadgeSummary ubs on ubs.UserId = c.Id
where c.TotalPostScore > 
    (
      select avg(TotalPostScore) 
      from UserPostStats 
      where TotalPostScore is not null
    )
and (c.ClosedQuestionsCount is null or c.ClosedQuestionsCount < 5)
group by
    c.Id,
    c.DisplayName,
    c.QuestionsAsked,
    c.AnswersProvided,
    c.TotalPostScore,
    c.CommentsMade,
    c.AvgCommentLength,
    c.ClosedQuestionsCount,
    c.ClosedAsDuplicate,
    c.MostRecentPostId,
    c.LatestPostScore,
    c.LatestBadgeName,
    c.LatestBadgeClass,
    c.TopTag,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges
order by c.TotalPostScore desc, c.CommentsMade desc
limit 50;