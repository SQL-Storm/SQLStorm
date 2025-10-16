-- {"query": "275.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1472} 
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
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> r.Id and not t.TagName = any(r.Path)
    where t.IsModeratorOnly = 0 and t.IsRequired = 0 and r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(v.VoteCount),0) as TotalVotesReceived,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as UpVotesReceived,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as DownVotesReceived,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1,2)
    left join Comments c on c.UserId = u.Id
    left join (
        select
            v.PostId,
            v.VoteTypeId,
            count(*) as VoteCount
        from Votes v
        group by v.PostId, v.VoteTypeId
    ) v on v.PostId = p.Id
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, ubc_gold.BadgeCount, ubc_silver.BadgeCount, ubc_bronze.BadgeCount
),
TopPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    where p.PostTypeId in (1,2) and p.Score > 0
),
PostWithAcceptedAnswer as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.CreationDate as QuestionCreationDate,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.OwnerUserId as AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerDisplayName
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
UserRecentActivity as (
    select
        u.Id as UserId,
        max(p.LastActivityDate) as LastPostActivity,
        max(c.CreationDate) as LastCommentActivity,
        greatest(
            coalesce(max(p.LastActivityDate), '1970-01-01'::timestamp),
            coalesce(max(c.CreationDate), '1970-01-01'::timestamp)
        ) as LastActivity
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.Location,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.TotalVotesReceived,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ura.LastActivity,
    tp.QuestionTitle as TopQuestionTitle,
    tp.AnswerScore as TopAnswerScore,
    pcr.CloseReasonName,
    pcr.CloseDate,
    string_agg(distinct rth.TagName, ', ') filter (where rth.Level = 1) as Level1Tags,
    string_agg(distinct rth.TagName, ', ') filter (where rth.Level = 2) as Level2Tags,
    string_agg(distinct rth.TagName, ', ') filter (where rth.Level = 3) as Level3Tags
from UserActivity ua
left join UserRecentActivity ura on ura.UserId = ua.UserId
left join PostWithAcceptedAnswer tp on tp.AnswerOwnerUserId = ua.UserId
left join PostCloseReasons pcr on pcr.PostId = tp.QuestionId
left join RecursiveTagHierarchy rth on rth.TagName = any(string_to_array(coalesce(tp.QuestionTitle, ''), ' '))
where ua.Reputation > 1000
group by
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.Location,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.TotalVotesReceived,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ura.LastActivity,
    tp.QuestionTitle,
    tp.AnswerScore,
    pcr.CloseReasonName,
    pcr.CloseDate
order by ua.Reputation desc, ua.GoldBadges desc, ua.SilverBadges desc
limit 100;