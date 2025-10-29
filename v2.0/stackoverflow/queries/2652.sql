-- {"query": "2652.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1396}
with RECURSIVE UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        coalesce(sum(v_count.UpVotes),0) as TotalUpVotesReceived,
        coalesce(sum(v_count.DownVotes),0) as TotalDownVotesReceived,
        max(p.LastActivityDate) as LastPostActivity,
        row_number() over (partition by u.Id order by max(p.CreationDate) desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select 
            PostId,
            count(case when vt.Name = 'UpMod' then 1 end) as UpVotes,
            count(case when vt.Name = 'DownMod' then 1 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by PostId
    ) v_count on v_count.PostId = p.Id
    group by u.Id, u.DisplayName
),
UserBadgeSummary as (
    select
        UserId,
        count(*) filter (where Class = 1) as GoldBadges,
        count(*) filter (where Class = 2) as SilverBadges,
        count(*) filter (where Class = 3) as BronzeBadges,
        bool_or(TagBased) as HasTagBasedBadges
    from Badges
    group by UserId
),
PostCloseSummary as (
    select
        p.Id as PostId,
        case 
            when ph.PostHistoryTypeId = 10 then ph.Comment
            else null
        end as CloseReasonId,
        crt.Name as CloseReasonName,
        p.OwnerUserId
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = CAST(coalesce(ph.Comment, '-1') AS integer)
),
DuplicateLinkSummary as (
    select
        pl.PostId,
        count(pl.Id) as OutboundLinks,
        count(distinct pl.RelatedPostId) as DistinctLinkedPosts,
        count(case when lt.Name = 'Duplicate' then 1 end) as DuplicateLinksCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
RankedPosts as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        pats.Name as PostTypeName,
        us.DisplayName as OwnerName,
        -- count tags by splitting and counting array length; handle null Tags
        array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'),1) as TagCount,
        ds.OutboundLinks,
        ds.DuplicateLinksCount,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    join PostTypes pats on pats.Id = p.PostTypeId
    left join Users us on us.Id = p.OwnerUserId
    left join DuplicateLinkSummary ds on ds.PostId = p.Id
    where p.PostTypeId in (1,2)
),
UserRankedPosts as (
    select
        uas.UserId,
        uas.DisplayName,
        rb.PostTypeName,
        count(rb.Id) filter (where rb.PostTypeName = 'Question') as TotalQuestions,
        count(rb.Id) filter (where rb.PostTypeName = 'Answer') as TotalAnswers,
        max(rb.ScoreRank) as MaxScoreRank,
        avg(rb.Score) as AveragePostScore,
        max(rb.ViewCount) as MaxViewCount
    from UserActivitySummary uas
    left join RankedPosts rb on rb.OwnerName = uas.DisplayName
    group by uas.UserId, uas.DisplayName, rb.PostTypeName
),
FinalResult as (
    select
        uas.UserId,
        uas.DisplayName,
        uas.QuestionsAsked,
        uas.AnswersGiven,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.HasTagBasedBadges,
        uas.TotalUpVotesReceived,
        uas.TotalDownVotesReceived,
        ua.MaxScoreRank,
        ua.AveragePostScore,
        ua.MaxViewCount,
        coalesce(pcs.CloseReasonName, 'Open') as MostFrequentCloseReason,
        (
            select count(*)
            from Posts p2
            join DuplicateLinkSummary dls2 on dls2.PostId = p2.Id
            where p2.OwnerUserId = uas.UserId
              and dls2.DuplicateLinksCount = (
                  select max(dls3.DuplicateLinksCount)
                  from Posts p3
                  join DuplicateLinkSummary dls3 on dls3.PostId = p3.Id
                  where p3.OwnerUserId = uas.UserId
              )
        ) as PostsWithMaxDuplicateLinks,
        rank() over (order by (uas.TotalUpVotesReceived - uas.TotalDownVotesReceived) desc) as ReputationRank,
        coalesce(NULLIF(u.WebsiteUrl,''), 'N/A') as Website
    from
        UserActivitySummary uas
    left join UserBadgeSummary ubs on ubs.UserId = uas.UserId
    left join UserRankedPosts ua on ua.UserId = uas.UserId
    left join (
        select
            p.OwnerUserId,
            ph.PostHistoryTypeId,
            crt.Name as CloseReasonName,
            count(*) as CloseCount
        from Posts p
        join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
        join CloseReasonTypes crt on crt.Id = CAST(ph.Comment AS integer)
        group by p.OwnerUserId, ph.PostHistoryTypeId, crt.Name
        order by CloseCount desc
        limit 1
    ) pcs on pcs.OwnerUserId = uas.UserId
    left join Users u on u.Id = uas.UserId
    group by
        uas.UserId,
        uas.DisplayName,
        uas.QuestionsAsked,
        uas.AnswersGiven,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.HasTagBasedBadges,
        uas.TotalUpVotesReceived,
        uas.TotalDownVotesReceived,
        ua.MaxScoreRank,
        ua.AveragePostScore,
        ua.MaxViewCount,
        pcs.CloseReasonName,
        u.WebsiteUrl,
        uas.UserId -- duplicate included harmlessly to ensure coverage
)
select *
from FinalResult
where QuestionsAsked > 5 or AnswersGiven > 10
order by ReputationRank
limit 100;