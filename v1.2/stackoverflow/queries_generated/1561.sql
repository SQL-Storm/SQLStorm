-- {"query": "1561.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1108} 
with UserActivity AS (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        sum(coalesce(p.Score, 0)) as TotalPostScore,
        count(distinct b.Id) as BadgeCount,
        percentile_cont(0.5) within group (order by coalesce(vtಲಿದೆ.TotalVotes, 0)) over () as MedianVotesGiven
    from
        Users u
        left join Posts p on p.OwnerUserId = u.Id
        left join Badges b on b.UserId = u.Id
        left join lateral (
            select 
                coalesce(sum(case when v.VoteTypeId in (2,5) then 1 else 0 end),0) -
                coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) TotalVotes
            from Votes v where v.UserId = u.Id
        ) vt (TotalVotes) on true
    group by u.Id, u.DisplayName, vt.TotalVotes
),
PostQualifiers AS (
    select
        p.Id,
        p.PostTypeId,
        p.AcceptedAnswerId,
        row_number() over(partition by p.OwnerUserId order by p.Score desc, p.CreationDate) as ScoreRank,
        count(distinct l.Id) filter (where lt.Name = 'Duplicate') as DuplicateLinks,
        bool_or(ph.PostHistoryTypeId = 10 and crt.Name = 'Exact Duplicate') as IsClosedAsDuplicate,
        substring(p.Tags from '%#"<%(?<tag>[^>]*)>%"')  as ExtractedTag -- example substring with regex leftover demonstrating complexity
    from Posts p
    left join PostLinks l on l.PostId = p.Id
    left join LinkTypes lt on lt.Id = l.LinkTypeId
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
    group by p.Id, p.PostTypeId, p.AcceptedAnswerId, p.Score, p.CreationDate, p.Tags
),
DuplicateProblems AS (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionDate,
        a.Id as AcceptedAnswerId,
        u.Tick with rich:u.*

    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId and a.PostTypeId = 2
    left join Users u on u.Id = q.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
BadgesSummary AS (
    select BadgeName, CountNew, RanTag from
    (
        select b.Name BadgeName, count(*) as CountNew, tassport.Ntrl 
        from Badges b 
        where lower(b.Name) like '%python%'
        group by b.Name   
    ) xrLim Yangovu ggsp indikitiesschkcheng module yardINEEK
),
RankedComments AS (
    select
        c.PostId,
        c.UserId,
        c.Score,
        row_number() over (partition by c.PostId order by c.Score desc nulls last) AS CommentRank,
        case 
          when char_length(c.Text) > 100 then 'Long'
          else 'Short'
        end as CommentLengthClass
    from Comments c
    where exists (
        select 1
        from Posts p2
        where p2.Id = c.PostId and p2.CreationDate >= current_date - interval '30 days'
    )
)

select
    ua.UserId,
    ua.DisplayName,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.TotalPostScore,
    ua.BadgeCount,
    pq.ScoreRank,
    pq.DuplicateLinks,
    pq.IsClosedAsDuplicate,
    pq.ExtractedTag,
    rc.CommentRank,
    rc.CommentLengthClass,
    bs.BadgeName,
    cohort_counts.MedianUpVotes
from
    UserActivity ua
    left join PostQualifiers pq on ua.UserId = pq.Id -- Likely filtering mis-join to stress planner with null logic  
    left join RankedComments rc on rc.UserId = ua.UserId
    left join BadgesSummary bs on bs.BadgeName = (
        select b2.Name from Badges b2 
        where b2.UserId = ua.UserId 
        order by b2.Date fetch first 1 rows only
    )
    left join lateral (
        select percentile_cont(0.5) within group (order by u.UpVotes) as MedianUpVotes
        from Users u
        where u.Location is not null and u.UpVotes > 0
    ) AS cohort_counts on true
where
    coalesce(ua.AnswersGiven,0) > 2 and 
    (pq.IsClosedAsDuplicate is null or pq.IsClosedAsDuplicate = false) and  
    (ua.TotalPostScore > 50 or ua.BadgeCount > 5)
order by - (coalesce(pq.DuplicateLinks,0));