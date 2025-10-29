-- {"query": "2433.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1311}
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count as InitialCount,
        p.Id as PostId,
        p.PostTypeId,
        array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'), 1) as NumTags
    from Tags t
    left join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
    where p.Id is not null
),
RankedUserBadges as (
    select
        b.UserId,
        b.Name,
        b.Class,
        row_number() over (partition by b.UserId order by b.Class, b.Date desc) as rn
    from Badges b
),
UserActivitySummaries as (
    select
        u.Id as UserId,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        coalesce(sum(vd.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vd.DownVotes),0) as TotalDownVotes,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 10) as TimesPostsClosed,
        min(u.CreationDate) over () as FirstUserCreated,
        max(u.LastAccessDate) over () as LastUserAccessed,
        case when max(u.LastAccessDate) > cast('2024-10-01 12:34:56' as timestamp) - interval '30 days' then 1 else 0 end as ActiveLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select
            p.OwnerUserId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        join Posts p on p.Id = v.PostId
        group by p.OwnerUserId
    ) vd on vd.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.CreationDate, u.LastAccessDate
),
DuplicateLinksWithReasons as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        ph.Comment as CloseReasonJSON,
        crt.Name as CloseReasonName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    left join lateral (
        select ph1.Comment
        from PostHistory ph1
        where ph1.PostId = pl.PostId and ph1.PostHistoryTypeId = 10
        order by ph1.CreationDate desc limit 1
    ) ph on true
    left join CloseReasonTypes crt on cast(crt.Id as text) = ph.Comment
    where lt.Name = 'Duplicate'
),
UserWindowStats as (
    select
        ua.UserId,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        ua.TimesPostsClosed,
        ua.ActiveLast30Days,
        sum(ua.QuestionsPosted) over (order by ua.UserId rows between 9 preceding and current row) as SumLast10UsersQuestions,
        avg(ua.TotalUpVotes) over (partition by ua.ActiveLast30Days) as AvgUpVotesActiveStatus
    from UserActivitySummaries ua
),
ComplexPostAnalysis as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        ua.UserId,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        coalesce(dl.LinkTypeName, 'None') as LinkTypeName,
        coalesce(dl.CloseReasonName, 'N/A') as CloseReasonName,
        (strpos(p.Title, 'SQL') > 0) as TitleContainsSQL,
        case
            when p.ViewCount > 10000 then 'HighView'
            when p.ViewCount between 1000 and 10000 then 'MediumView'
            else 'LowView'
        end as ViewCategory,
        length(coalesce(p.Body, '')) as BodyLength,
        row_number() over (partition by ua.UserId order by p.CreationDate desc) as PostRankDescByUser
    from Posts p
    left join UserActivitySummaries ua on ua.UserId = p.OwnerUserId
    left join DuplicateLinksWithReasons dl on dl.PostId = p.Id
    where p.PostTypeId = 1 and p.Title is not null and p.Tags is not null
)
select
    cpa.Id as PostId,
    cpa.Title,
    cpa.CreationDate,
    cpa.Score,
    cpa.ViewCount,
    cpa.ViewCategory,
    cpa.AnswerCount,
    cpa.FavoriteCount,
    cpa.Tags,
    concat(
        'UserID: ', cast(cpa.UserId as text),
        ', Qs: ', cast(cpa.QuestionsPosted as text),
        ', Ans: ', cast(cpa.AnswersPosted as text),
        ', PostRank: ', cast(cpa.PostRankDescByUser as text)
    ) as UserStatsSummary,
    cpa.LinkTypeName,
    cpa.CloseReasonName,
    cpa.TitleContainsSQL,
    cpa.BodyLength,
    uws.SumLast10UsersQuestions,
    uws.AvgUpVotesActiveStatus
from ComplexPostAnalysis cpa
join UserWindowStats uws on uws.UserId = cpa.UserId
where cpa.Score > (
    select avg(Score) from Posts where PostTypeId = 1
)
and (cpa.TitleContainsSQL = true or cpa.FavoriteCount > 5)
and (cpa.CloseReasonName = 'N/A' or cpa.CloseReasonName is null)
order by cpa.Score desc, cpa.CreationDate desc
limit 100;