-- {"query": "163.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1560} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Level + 1,
        r.Path || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id = r.Id + 1
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
UserReputationStats as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(ubc_gold.BadgeCount, 0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount, 0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount, 0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join UserBadgeCounts ubc_gold on u.Id = ubc_gold.UserId and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on u.Id = ubc_silver.UserId and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on u.Id = ubc_bronze.UserId and ubc_bronze.Class = 3
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserTopQuestionRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId is null then 1 else 0 end) as AnonymousAnswers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PostsLast30Days,
        sum(p.Score) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as ScoreLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
UserCommentStats as (
    select
        c.UserId,
        count(*) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        sum(case when c.CreationDate > now() - interval '90 days' then 1 else 0 end) as RecentComments
    from Comments c
    group by c.UserId
),
CombinedUserStats as (
    select
        urs.Id,
        urs.DisplayName,
        urs.Reputation,
        urs.GoldBadges,
        urs.SilverBadges,
        urs.BronzeBadges,
        ua.PostsLast30Days,
        ua.ScoreLast30Days,
        coalesce(ucs.CommentCount, 0) as CommentCount,
        coalesce(ucs.AvgCommentLength, 0) as AvgCommentLength,
        coalesce(ucs.RecentComments, 0) as RecentComments
    from UserReputationStats urs
    left join (
        select
            UserId,
            max(PostsLast30Days) as PostsLast30Days,
            max(ScoreLast30Days) as ScoreLast30Days
        from UserActivityWindow
        group by UserId
    ) ua on urs.Id = ua.UserId
    left join UserCommentStats ucs on urs.Id = ucs.UserId
)
select distinct
    tq.Id as QuestionId,
    tq.Title,
    tq.OwnerUserId,
    urs.DisplayName as OwnerDisplayName,
    urs.Reputation,
    urs.GoldBadges,
    urs.SilverBadges,
    urs.BronzeBadges,
    tq.Score as QuestionScore,
    tq.ViewCount,
    as_.AnswerCount,
    as_.AvgAnswerScore,
    as_.MaxAnswerScore,
    as_.AnonymousAnswers,
    qcr.CloseReason,
    qcr.CloseDate,
    cu.CommentCount,
    cu.AvgCommentLength,
    cu.RecentComments,
    cu.PostsLast30Days,
    cu.ScoreLast30Days,
    string_agg(distinct rth.TagName, ', ') filter (where rth.Level = 1) as TopLevelTags,
    string_agg(distinct rth.TagName, ', ') filter (where rth.Level = 2) as SecondLevelTags,
    string_agg(distinct rth.TagName, ', ') filter (where rth.Level = 3) as ThirdLevelTags,
    case
        when tq.AcceptedAnswerId is not null then 'Accepted'
        else 'No Accepted Answer'
    end as AcceptedAnswerStatus,
    case
        when urs.Reputation > 10000 then 'High Rep'
        when urs.Reputation between 1000 and 10000 then 'Medium Rep'
        else 'Low Rep'
    end as ReputationCategory,
    coalesce(tq.Tags, '') as RawTags,
    length(coalesce(tq.Title, '')) as TitleLength,
    length(coalesce(tq.Tags, '')) as TagsLength
from TopQuestions tq
left join AnswerStats as_ on tq.Id = as_.QuestionId
left join QuestionCloseReasons qcr on tq.Id = qcr.PostId
left join CombinedUserStats cu on tq.OwnerUserId = cu.Id
left join UserReputationStats urs on tq.OwnerUserId = urs.Id
left join RecursiveTagHierarchy rth on position(rth.TagName in coalesce(tq.Tags, '')) > 0
where
    (tq.Score > 50 or as_.MaxAnswerScore > 20)
    and (qcr.CloseDate is null or qcr.CloseDate > now() - interval '1 year')
order by
    tq.Score desc,
    as_.MaxAnswerScore desc,
    urs.Reputation desc
limit 100;