with UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) as TotalBadges,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        coalesce(max(b.Date), cast('1970-01-01' as date)) as LastBadgeDate,
        u.Reputation
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
), TopPostsCTE as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        row_number() over(partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn_score_desc
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1, 2) and p.CreationDate > (cast('2024-10-01' as date) - interval '1 year')
), PostAnswerStats as (
    select
        q.Id as QuestionId,
        count(a.Id) as TotalAnswers,
        max(a.Score) as MaxAnswerScore,
        avg(case when a.Score > 0 then a.Score end) as AvgPositiveAnswerScore,
        sum(case when a.Score < 0 then 1 else 0 end) as NegativeScoreAnswerCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id
), DuplicateLinkCount as (
    select
        pl.PostId,
        count(*) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
), CloseReasonsCount as (
    select
        ph.PostId,
        count(distinct case when ph.PostHistoryTypeId = 10 then ph.Id end) as CloseVotes,
        count(distinct case when ph.PostHistoryTypeId = 11 then ph.Id end) as ReopenVotes,
        string_agg(distinct crt.Name, ', ' order by crt.Name) as CloseReasonNames
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer) and ph.PostHistoryTypeId = 10
    group by ph.PostId
), UserActivityWindow as (
    select
        PhUserId,
        PhPostId,
        PhUserBadgeDate,
        PhBadgeName,
        sum(case when PostTypeId = 1 then 1 else 0 end) over (partition by PhUserId order by PhUserBadgeDate rows between unbounded preceding and current row) as CumulativeQuestions,
        sum(case when PostTypeId = 2 then 1 else 0 end) over (partition by PhUserId order by PhUserBadgeDate rows between unbounded preceding and current row) as CumulativeAnswers
    from (
        select
            ph.UserId as PhUserId,
            ph.PostId as PhPostId,
            ph.CreationDate as PhUserBadgeDate,
            b.Name as PhBadgeName,
            p.PostTypeId
        from PostHistory ph
        inner join Posts p on p.Id = ph.PostId
        left join Badges b on b.UserId = ph.UserId and b.Date = ph.CreationDate
        where ph.UserId is not null
    ) sub
)
select 
    ubs.UserId,
    ubs.DisplayName as UserDisplayName,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.LastBadgeDate,
    coalesce(lpc.DuplicateCount, 0) as PostDuplicateReferences,
    coalesce(crc.CloseVotes, 0) as CloseVotesCount,
    coalesce(crc.ReopenVotes, 0) as ReopenVotesCount,
    crc.CloseReasonNames,
    tas.TotalAnswers,
    tas.MaxAnswerScore,
    round(coalesce(tas.AvgPositiveAnswerScore,0),2) as AvgPosAnswerScore,
    tas.NegativeScoreAnswerCount,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.Tags,
    length(tp.Tags) as TagsLength,
    case 
        when tp.Tags is null then -1
        else array_length(string_to_array(substring(tp.Tags from 2 for length(tp.Tags) - 2), '><'),1)
    end as NumTags,
    case 
        when tp.Title is null or length(trim(tp.Title)) = 0 then 'NoTitle'
        else 
            concat(
                upper(substring(tp.Title from 1 for 1)),
                lower(substring(tp.Title from 2 for length(tp.Title)))
            )
    end as NormalizedTitle,
    (
        select length(max(c.Text)) 
        from Comments c 
        where c.PostId = tp.Id and c.Text is not null
    ) as LatestCommentTextLength,
    (
        select count(*) 
        from Votes v 
        where v.PostId = tp.Id 
          and v.VoteTypeId = 2
          and v.CreationDate > (cast('2024-10-01' as date) - interval '6 months')
    ) as RecentUpvotesCount,
    rank() over(partition by tp.OwnerUserId order by tp.Score desc) as UserPostScoreRank,
    (select count(*) from (
        select UserId as uid from Badges where Class = 1
        union
        select Id as uid from Users where Reputation > 10000
    ) as combined_ids where combined_ids.uid = ubs.UserId) as IsGoldBadgeHolderOrHighRep
from UserBadgeStats ubs
left join TopPostsCTE tp on tp.OwnerUserId = ubs.UserId and tp.rn_score_desc = 1
left join PostAnswerStats tas on tas.QuestionId = tp.Id
left join DuplicateLinkCount lpc on lpc.PostId = tp.Id
left join CloseReasonsCount crc on crc.PostId = tp.Id
where ubs.TotalBadges > 0
group by
    ubs.UserId,
    ubs.DisplayName,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.LastBadgeDate,
    lpc.DuplicateCount,
    crc.CloseVotes,
    crc.ReopenVotes,
    crc.CloseReasonNames,
    tas.TotalAnswers,
    tas.MaxAnswerScore,
    tas.AvgPositiveAnswerScore,
    tas.NegativeScoreAnswerCount,
    tp.Id,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.Tags,
    tp.OwnerUserId,
    tp.rn_score_desc,
    ubs.Reputation
order by ubs.GoldBadges desc, ubs.Reputation desc
limit 100;