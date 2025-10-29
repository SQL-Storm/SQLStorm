-- {"query": "2767.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1524} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        p.Id as PostId,
        1 as Depth
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
    where t.IsModeratorOnly = 0

    union all

    select
        rt.Id,
        rt.TagName,
        rt.Count,
        rt.AnswerCount,
        p.Id,
        rt.Depth + 1
    from RecursiveTagCounts rt
    join Posts p on p.ParentId = rt.PostId
    where rt.Depth < 3
),
UserBadgeScores as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(coalesce(p.Score,0)) as TotalPostScore,
        avg(coalesce(p.Score,0)) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        avg(coalesce(p.Score,0)) filter (where p.PostTypeId = 2) as AvgAnswerScore,
        max(p.CreationDate) as LastPostDate,
        count(distinct p.Id) as TotalPosts,
        max(u.Reputation) as Reputation
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
RankedPosts as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        p.Tags,
        u.DisplayName,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.CreationDate desc) as ScoreRank,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as PostRecencyRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1,2) and p.Score is not null
),
LatestCommentsWithScore as (
    select
        c.Id,
        c.PostId,
        c.Text,
        c.Score as CommentScore,
        c.CreationDate,
        c.UserId,
        u.DisplayName as CommenterName,
        row_number() over (partition by c.PostId order by c.CreationDate desc) as rn
    from Comments c
    left join Users u on u.Id = c.UserId
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    join CloseReasonTypes crt on crt.Id = convert(int, ph.Comment) filter (where ph.PostHistoryTypeId = 10)
    where ph.PostHistoryTypeId = 10
),
CombinedUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(p.QCount, 0) as QuestionCount,
        coalesce(p.ACount, 0) as AnswerCount,
        coalesce(c.CCount, 0) as CommentCount,
        coalesce(v.UpVotes, 0) as UpVotes,
        coalesce(v.DownVotes, 0) as DownVotes
    from Users u
    left join (
        select
            OwnerUserId,
            count(*) filter (where PostTypeId = 1) as QCount,
            count(*) filter (where PostTypeId = 2) as ACount
        from Posts
        group by OwnerUserId
    ) p on p.OwnerUserId = u.Id
    left join (
        select
            UserId,
            count(*) as CCount
        from Comments
        group by UserId
    ) c on c.UserId = u.Id
    left join (
        select
            v.UserId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
        group by v.UserId
    ) v on v.UserId = u.Id
)
select distinct
    rt.Id as TagId,
    rt.TagName,
    rt.Count as TagCount,
    rt.AnswerCount,
    ubs.UserId,
    ubs.DisplayName as UserDisplayName,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.TotalPostScore,
    ubs.AvgQuestionScore,
    ubs.AvgAnswerScore,
    rp.Id as PostId,
    rp.Title as PostTitle,
    rp.PostTypeId,
    rp.Score as PostScore,
    rp.CreationDate as PostCreated,
    lc.Text as LatestCommentText,
    lc.CommentScore,
    pcr.CloseReasonName,
    cua.QuestionCount,
    cua.AnswerCount,
    cua.CommentCount,
    cua.UpVotes,
    cua.DownVotes,
    case 
        when rp.PostTypeId = 1 and rp.AcceptedAnswerId is not null then 'Accepted'
        when rp.PostTypeId = 2 and exists (
            select 1 from Posts p2 where p2.AcceptedAnswerId = rp.Id
        ) then 'AnswerAccepted'
        else 'NoAcceptance'
    end as AcceptanceStatus,
    coalesce(rtc.Depth, 0) as TagDepth,
    (length(coalesce(rp.Title, '')) - length(replace(coalesce(rp.Title, ''), ' ', ''))) as TitleWordCount,
    case 
        when rp.Tags is not null then array_length(string_to_array(substring(rp.Tags from 2 for length(rp.Tags)-2), '><'), 1)
        else 0
    end as TagCountInPost,
    row_number() over (partition by ubs.UserId order by rp.Score desc) as RankByUserPostScore
from RecursiveTagCounts rt
left join Users ubs on ubs.Id = (
    select OwnerUserId from Posts p where p.Id = rt.PostId limit 1
)
left join RankedPosts rp on rp.Id = rt.PostId
left join LatestCommentsWithScore lc on lc.PostId = rp.Id and lc.rn = 1
left join PostCloseReasons pcr on pcr.PostId = rp.Id
left join CombinedUserActivity cua on cua.UserId = ubs.UserId
where rt.Depth <= 3
  and ubs.Reputation > 1000
  and (rp.Score > 5 or rp.PostTypeId = 1)
order by ubs.GoldBadges desc, rp.Score desc, rt.Count desc
limit 100;