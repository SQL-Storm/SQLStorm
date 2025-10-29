-- {"query": "2194.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1271} 
with UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) as TotalBadges,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionStats as (
    select
        p.Id as QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        coalesce(p.Score,0) as Score,
        coalesce(p.ViewCount,0) as ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        -- Extract tags array from Tags string field like '<tag1><tag2>'
        string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><') as TagArray,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as RankByScore
    from Posts p
    where p.PostTypeId = 1
),
AnswerStats as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.CreationDate,
        coalesce(a.Score,0) as Score,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        case when p.AcceptedAnswerId = a.Id then 1 else 0 end as IsAccepted
    from Posts a
    left join Posts p on p.Id = a.ParentId
    left join (
        select 
            PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by PostId
    ) v on v.PostId = a.Id
    where a.PostTypeId = 2
),
TopTags as (
    select
        tag,
        count(*) as UsageCount
    from (
        select unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as tag
        from Posts p
        where p.PostTypeId = 1
    ) sq
    group by tag
    order by UsageCount desc
    limit 10
),
UserTagScore as (
    select
        u.Id as UserId,
        tag,
        sum(p.Score) as TotalScore
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    cross join unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as tag
    group by u.Id, tag
),
FilteredUserTagScore as (
    select
        uts.UserId,
        uts.tag,
        uts.TotalScore
    from UserTagScore uts
    join TopTags tt on tt.tag = uts.tag
),
RankedUserTags as (
    select
        UserId,
        tag,
        TotalScore,
        rank() over (partition by UserId order by TotalScore desc) as TagRank
    from FilteredUserTagScore
),
LatestCloseReasons as (
    select distinct on (ph.PostId)
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
    order by ph.PostId, ph.CreationDate desc
),
QuestionStatus as (
    select
        q.QuestionId,
        coalesce(lcr.CloseReasonName, 'Open') as Status,
        lcr.CloseDate
    from QuestionStats q
    left join LatestCloseReasons lcr on lcr.PostId = q.QuestionId
)
select 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    qs.QuestionId,
    qs.CreationDate as QuestionCreationDate,
    qs.Score as QuestionScore,
    qs.ViewCount as QuestionViews,
    qs.AnswerCount,
    qs.FavoriteCount,
    qs.TagArray,
    rst.AnswerId,
    rst.Score as AnswerScore,
    rst.UpVotes as AnswerUpVotes,
    rst.DownVotes as AnswerDownVotes,
    rst.IsAccepted,
    qst.Status as QuestionStatus,
    qst.CloseDate,
    rtag.tag as TopUserTag,
    rtag.TotalScore as TopTagScore
from Users u
left join UserBadgeStats ubs on ubs.UserId = u.Id
left join QuestionStats qs on qs.OwnerUserId = u.Id and qs.RankByScore <= 3
left join lateral (
    select 
        a.AnswerId,
        a.Score,
        a.UpVotes,
        a.DownVotes,
        a.IsAccepted
    from AnswerStats a
    where a.OwnerUserId = u.Id
    order by a.Score desc nulls last
    limit 1
) rst on true
left join QuestionStatus qst on qst.QuestionId = qs.QuestionId
left join RankedUserTags rtag on rtag.UserId = u.Id and rtag.TagRank = 1
where u.Reputation > 1000
order by u.Reputation desc, qs.Score desc
limit 100;