-- {"query": "2628.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1978} 
with UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(sum(case when b.Class = 1 then 1 else 0 end), 0) as GoldBadges,
        coalesce(sum(case when b.Class = 2 then 1 else 0 end), 0) as SilverBadges,
        coalesce(sum(case when b.Class = 3 then 1 else 0 end), 0) as BronzeBadges,
        rank() over(order by u.Reputation desc) as ReputationRank,
        count(distinct b.Id) as TotalBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
PostActivitySummary as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        -- Count of comments per post
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        -- Count of unique users who commented
        (select count(distinct coalesce(c.UserId, -1)) from Comments c where c.PostId = p.Id) as UniqueCommentUsers,
        -- Number of times post was closed (PostHistoryTypeId=10)
        (select count(*) from PostHistory ph where ph.PostId = p.Id and ph.PostHistoryTypeId = 10) as CloseVotes,
        -- Average score of answers if post is a question
        (select avg(cast(ans.Score as float)) from Posts ans where ans.ParentId = p.Id and ans.PostTypeId = 2) as AvgAnswerScore,
        -- Max answer score
        (select max(ans.Score) from Posts ans where ans.ParentId = p.Id and ans.PostTypeId = 2) as MaxAnswerScore,
        -- Boolean whether accepted answer is among top 3 scoring answers
        (case 
            when p.AcceptedAnswerId is null then null
            else (
                select case when p.AcceptedAnswerId in (
                    select ans.Id from Posts ans where ans.ParentId = p.Id and ans.PostTypeId = 2
                    order by ans.Score desc limit 3
                ) then 1 else 0 end
            )
        end) as AcceptedAnswerInTop3,
        -- Concatenate first three tags (assuming tags formatted as '<tag1><tag2><tag3>')
        substring(string_agg(tag, ', ') within group (order by tag) from 1 for 100) as ConcatenatedTags
    from Posts p
    join Users u on u.Id = p.OwnerUserId
    left join lateral (
        select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as tag
    ) as taglist on true
    where p.PostTypeId = 1
    group by p.Id, p.PostTypeId, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.AnswerCount, p.AcceptedAnswerId, u.DisplayName
),
RankedQuestions as (
    select
        pas.*,
        row_number() over(partition by pas.OwnerUserId order by pas.ViewCount desc, pas.Score desc) as QuestionRankByUser
    from PostActivitySummary pas
),
FilteredQuestions as (
    select * from RankedQuestions
    where QuestionRankByUser <= 5
),
UserQuestionStats as (
    select
        fq.OwnerUserId,
        count(*) as NumQuestions,
        avg(fq.ViewCount) as AvgViewCount,
        avg(fq.Score) as AvgScore,
        avg(coalesce(fq.AvgAnswerScore, 0)) as AvgAnswerScore,
        sum(case when fq.AcceptedAnswerInTop3 = 1 then 1 else 0 end) as AcceptedAnswerInTop3Count,
        avg(fq.CommentCount) as AvgComments,
        avg(fq.UniqueCommentUsers) as AvgUniqueCommenters
    from FilteredQuestions fq
    group by fq.OwnerUserId
),
HighlyEngagedUsers as (
    select
        u.Id,
        u.DisplayName,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.ReputationRank,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(u.AboutMe, '') as AboutMe,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.LastAccessDate,
        u.WebsiteUrl,
        coalesce(u.EmailHash, '') as EmailHash,
        u.AccountId,
        uqa.NumQuestions,
        uqa.AvgViewCount,
        uqa.AvgScore,
        uqa.AvgAnswerScore,
        uqa.AcceptedAnswerInTop3Count,
        uqa.AvgComments,
        uqa.AvgUniqueCommenters
    from Users u
    join UserBadgeCounts ub on ub.UserId = u.Id
    left join UserQuestionStats uqa on uqa.OwnerUserId = u.Id
    where ub.GoldBadges > 2
      and u.Reputation > 10000
      and uqa.NumQuestions > 0
),
RecentCloseReasons as (
    select
        ph.PostId,
        ph.Comment as CloseReasonId,
        count(*) as CloseCount
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
      and ph.CreationDate > now() - interval '30 days'
      and ph.Comment is not null
    group by ph.PostId, ph.Comment
),
RecentClosedPosts as (
    select distinct ph.PostId from PostHistory ph where ph.PostHistoryTypeId = 10 and ph.CreationDate > now() - interval '30 days'
),
UserCloseAttention as (
    select
        u.Id as UserId,
        count(distinct rcp.PostId) as RecentClosedPosts,
        sum(coalesce(rc.CloseCount, 0)) as RecentCloseCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join RecentClosedPosts rcp on rcp.PostId = p.Id
    left join RecentCloseReasons rc on rc.PostId = p.Id
    group by u.Id
),
FinalUserStats as (
    select
        hu.*,
        uca.RecentClosedPosts,
        uca.RecentCloseCount,
        -- Calculate ratio of accepted accepted answers among top 3 answers per question
        case when hu.NumQuestions > 0 then (hu.AcceptedAnswerInTop3Count::float / hu.NumQuestions) else null end as AcceptedAnswerTop3Ratio,
        -- Length of AboutMe after trimming
        length(trim(hu.AboutMe)) as AboutMeLength
    from HighlyEngagedUsers hu
    left join UserCloseAttention uca on uca.UserId = hu.Id
)
select
    fus.Id as UserId,
    fus.DisplayName,
    fus.Reputation,
    fus.ReputationRank,
    fus.GoldBadges,
    fus.SilverBadges,
    fus.BronzeBadges,
    fus.NumQuestions,
    round(fus.AvgViewCount,2) as AvgViewCount,
    round(fus.AvgScore,2) as AvgQuestionScore,
    round(fus.AvgAnswerScore,2) as AvgAnswerScore,
    fus.AcceptedAnswerInTop3Count,
    round(fus.AcceptedAnswerTop3Ratio::numeric,3) as AcceptedInTop3Ratio,
    fus.AvgComments,
    fus.AvgUniqueCommenters,
    fus.RecentClosedPosts,
    fus.RecentCloseCount,
    fus.AboutMeLength,
    -- Show URL or fallback string if null or empty after trimming
    case when coalesce(trim(fus.WebsiteUrl), '') = '' then 'No website' else fus.WebsiteUrl end as WebsiteUrl,
    -- Extract domain from WebsiteUrl if present using regex, else NULL
    regexp_replace(fus.WebsiteUrl, '^https?://([^/]+).*$', '\1') as WebsiteDomain,
    -- Boolean if user recently accessed in last 30 days
    (fus.LastAccessDate > now() - interval '30 days') as RecentlyActive,
    -- Using a set operation to find badges not held by user from top 5 badge names who have most distinct users
    (
        select string_agg(bt.Name, ', ') from (
            select distinct b.Name
            from Badges b
            order by (select count(distinct b2.UserId) from Badges b2 where b2.Name = b.Name) desc
            limit 5
        ) bt
        except
        select b2.Name
        from Badges b2
        where b2.UserId = fus.Id
    ) as MissingTopBadges,
    -- Conditional string showing moderate user activity details
    case 
        when fus.Views > 100000 then 'Power User'
        when fus.Views > 10000 then 'Active User'
        else 'New User'
    end as UserActivityLevel
from FinalUserStats fus
order by fus.ReputationRank
limit 100;