-- {"query": "363.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1492} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews,
        row_number() over (partition by t.IsModeratorOnly order by t.Count desc) as TagRank
    from Tags t
    left join (
        select
            unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag,
            count(*) filter (where p.PostTypeId = 2) as AnswerCount,
            sum(p.ViewCount) as ViewCount
        from Posts p
        where p.Tags is not null
        group by Tag
    ) p on p.Tag = t.TagName
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        count(c.Id) over (partition by p.Id) as CommentCount,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId in (1, 2)
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
AnswerScoresWithWindow as (
    select
        a.Id,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
TopAnswersPerQuestion as (
    select
        a.QuestionId,
        a.Id as AnswerId,
        a.Score,
        a.CreationDate
    from AnswerScoresWithWindow a
    where a.AnswerRank = 1
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersCount,
        coalesce(sum(vt.UpVotes), 0) as TotalUpVotes,
        coalesce(sum(vt.DownVotes), 0) as TotalDownVotes,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select
            p.OwnerUserId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        left join VoteTypes vt on vt.Id = v.VoteTypeId
        where p.OwnerUserId is not null
        group by p.OwnerUserId
    ) vt on vt.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
)
select
    rtc.TagName,
    rtc.Count as TagUsageCount,
    rtc.TotalAnswers,
    rtc.TotalViews,
    case when rtc.TagRank <= 5 then 'Top5' else 'Other' end as TagPopularityGroup,
    ubs.DisplayName as BadgeOwner,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.LastBadgeDate,
    pas.AnswerId as TopAnswerId,
    pas.Score as TopAnswerScore,
    pas.CreationDate as TopAnswerCreationDate,
    ca.CloseDate,
    ca.CloseReason,
    ca.ClosedByUserName,
    uas.TotalPosts as UserTotalPosts,
    uas.QuestionsCount,
    uas.AnswersCount,
    uas.TotalUpVotes,
    uas.TotalDownVotes,
    uas.LastPostDate,
    pa.PostTypeId,
    pa.Score,
    pa.ViewCount,
    pa.CommentCount,
    pa.Tags,
    case
        when pa.Score >= 100 then 'HighScore'
        when pa.Score between 50 and 99 then 'MediumScore'
        else 'LowScore'
    end as ScoreCategory,
    case
        when pa.Tags is null then 'NoTags'
        when position('sql' in lower(pa.Tags)) > 0 then 'ContainsSQL'
        else 'OtherTags'
    end as TagPresence,
    case
        when pa.LastActivityDate is null then 'NoActivity'
        when pa.LastActivityDate > now() - interval '30 days' then 'ActiveLast30Days'
        else 'InactiveLast30Days'
    end as RecentActivityStatus
from RecursiveTagCounts rtc
left join UserBadgeSummary ubs on ubs.UserId = (
    select OwnerUserId from Posts p where p.Tags like '%' || rtc.TagName || '%' limit 1
)
left join TopAnswersPerQuestion pas on pas.QuestionId = (
    select p.Id from Posts p where p.Tags like '%' || rtc.TagName || '%' and p.PostTypeId = 1 limit 1
)
left join ClosedQuestionsWithReasons ca on ca.PostId = pas.QuestionId
left join UserActivitySummary uas on uas.Id = ubs.UserId
left join PostActivityWindow pa on pa.Id = pas.AnswerId
where rtc.Count > 1000
union
select
    t.TagName,
    t.Count,
    0,
    0,
    'NoData',
    null,
    0,
    0,
    0,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null
from Tags t
where t.Count <= 1000
order by TagUsageCount desc, TagName asc
limit 100;