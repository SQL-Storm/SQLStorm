-- {"query": "321.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1720} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id as OwnerUserId,
        u.DisplayName,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    join Posts p on p.Tags like concat('%<', t.TagName, '>%') and p.PostTypeId = 1
    left join Users u on u.Id = p.OwnerUserId
    where t.Count > 1000
),
TopPostsPerTag as (
    select * from RecursiveTagCounts where rn <= 5
),
UserBadgeCounts as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges
    from Badges b
    group by b.UserId
),
UserActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(ub.GoldBadges,0) as GoldBadges,
        coalesce(ub.SilverBadges,0) as SilverBadges,
        coalesce(ub.BronzeBadges,0) as BronzeBadges,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1) as QuestionCount,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as AnswerCount,
        (select avg(p.Score) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as AvgAnswerScore
    from Users u
    left join UserBadgeCounts ub on ub.UserId = u.Id
    where u.Reputation > 1000
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
PostVoteSummary as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then v.BountyAmount else 0 end) as TotalBounty
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
AnswerRanks as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        coalesce(pc.CloseReason, 'Open') as CloseReason,
        coalesce(pvs.UpVotes, 0) as QuestionUpVotes,
        coalesce(pvs.DownVotes, 0) as QuestionDownVotes,
        coalesce(pvs.TotalBounty, 0) as QuestionBounty,
        count(a.AnswerId) as TotalAnswers,
        max(case when a.AnswerRank = 1 then a.Score else null end) as TopAnswerScore,
        min(case when a.AnswerRank = 1 then a.AnswerId else null end) as TopAnswerId
    from Posts q
    left join PostCloseReasons pc on pc.PostId = q.Id
    left join PostVoteSummary pvs on pvs.PostId = q.Id
    left join AnswerRanks a on a.QuestionId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, pc.CloseReason, pvs.UpVotes, pvs.DownVotes, pvs.TotalBounty
),
UserAnswerDetails as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as AcceptedAnswerCount,
        max(a.Score) as MaxAnswerScore,
        min(a.CreationDate) as FirstAnswerDate,
        max(a.CreationDate) as LastAnswerDate
    from Users u
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join Posts q on q.Id = a.ParentId
    group by u.Id, u.DisplayName
),
ComplexStringAnalysis as (
    select
        p.Id as PostId,
        p.Title,
        length(p.Body) as BodyLength,
        length(regexp_replace(p.Body, '[^a-zA-Z]', '', 'g')) as AlphaChars,
        length(regexp_replace(p.Body, '[^0-9]', '', 'g')) as NumericChars,
        case
            when p.Tags is null then 0
            else array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'), 1)
        end as TagCount,
        coalesce(pc.CloseReason, 'Open') as CloseReason
    from Posts p
    left join PostCloseReasons pc on pc.PostId = p.Id
    where p.PostTypeId = 1
),
FinalSelection as (
    select
        qas.QuestionId,
        qas.Title,
        qas.CreationDate as QuestionCreation,
        qas.QuestionScore,
        qas.ViewCount,
        qas.CloseReason,
        qas.QuestionUpVotes,
        qas.QuestionDownVotes,
        qas.QuestionBounty,
        qas.TotalAnswers,
        qas.TopAnswerScore,
        uad.UserId as TopAnswerUserId,
        uad.DisplayName as TopAnswerUserName,
        uad.AnswerCount as TopAnswerUserAnswerCount,
        uad.AvgAnswerScore as TopAnswerUserAvgScore,
        uad.AcceptedAnswerCount as TopAnswerUserAcceptedCount,
        csa.BodyLength,
        csa.AlphaChars,
        csa.NumericChars,
        csa.TagCount,
        utc.TagName,
        utc.Count as TagGlobalCount,
        utc.Score as TagTopPostScore
    from QuestionAnswerStats qas
    left join Posts ta on ta.Id = qas.TopAnswerId
    left join UserAnswerDetails uad on uad.UserId = ta.OwnerUserId
    left join ComplexStringAnalysis csa on csa.PostId = qas.QuestionId
    left join TopPostsPerTag utc on utc.PostId = qas.QuestionId
    where qas.QuestionScore > 10 and qas.TotalAnswers > 2
)
select distinct
    fs.QuestionId,
    fs.Title,
    fs.QuestionCreation,
    fs.QuestionScore,
    fs.ViewCount,
    fs.CloseReason,
    fs.QuestionUpVotes,
    fs.QuestionDownVotes,
    fs.QuestionBounty,
    fs.TotalAnswers,
    fs.TopAnswerScore,
    fs.TopAnswerUserId,
    fs.TopAnswerUserName,
    fs.TopAnswerUserAnswerCount,
    fs.TopAnswerUserAvgScore,
    fs.TopAnswerUserAcceptedCount,
    fs.BodyLength,
    fs.AlphaChars,
    fs.NumericChars,
    fs.TagCount,
    fs.TagName,
    fs.TagGlobalCount,
    fs.TagTopPostScore
order by fs.QuestionScore desc, fs.ViewCount desc, fs.TotalAnswers desc
limit 100;